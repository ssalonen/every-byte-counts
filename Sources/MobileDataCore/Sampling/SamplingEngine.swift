import Foundation

/// What a single sampling pass produced.
public struct SampleResult: Equatable, Sendable {
    public var snapshot: Snapshot
    public var didReboot: Bool
    public var didRolloverCycle: Bool
    /// Alerts that were newly crossed and should be posted as notifications.
    public var pendingAlerts: [PendingAlert]

    public init(snapshot: Snapshot, didReboot: Bool, didRolloverCycle: Bool, pendingAlerts: [PendingAlert]) {
        self.snapshot = snapshot
        self.didReboot = didReboot
        self.didRolloverCycle = didRolloverCycle
        self.pendingAlerts = pendingAlerts
    }
}

/// The "take a sample" routine shared by the app (on launch/foreground) and the
/// widget (on each timeline refresh) — design §4. It is **idempotent and cheap**:
/// it reads the counter, applies reboot handling, rolls the billing cycle over
/// when due, appends a snapshot, evaluates alerts and persists, all in one
/// synchronous pass that is safe to call at unpredictable times.
public final class SamplingEngine {
    private let store: DataStore
    private let reader: CounterReader
    private let calendar: BillingCycleCalendar
    private let aggregator: DailyAggregator
    private let alertEvaluator: AlertEvaluator

    /// How many raw snapshots to keep. Daily/cycle aggregates summarise older
    /// data, so the raw stream only needs roughly a cycle's worth for the daily
    /// view. ~6 samples/day × 70 days ≈ generous headroom.
    public let snapshotRetentionLimit: Int

    public init(
        store: DataStore,
        reader: CounterReader,
        calendar: BillingCycleCalendar = BillingCycleCalendar(),
        aggregator: DailyAggregator = DailyAggregator(),
        alertEvaluator: AlertEvaluator = AlertEvaluator(),
        snapshotRetentionLimit: Int = 500
    ) {
        self.store = store
        self.reader = reader
        self.calendar = calendar
        self.aggregator = aggregator
        self.alertEvaluator = alertEvaluator
        self.snapshotRetentionLimit = snapshotRetentionLimit
    }

    /// Reads the counter and folds the result into persisted state. Returns `nil`
    /// only if the counter could not be read (state is left untouched).
    @discardableResult
    public func sample(now: Date = Date()) -> SampleResult? {
        guard let reading = try? reader.read() else { return nil }

        var state = store.load()
        if state.installDate == nil { state.installDate = now }

        // 1. Fold the raw reading into the monotonic cumulative totals.
        let (cumulativeCellular, cumulativeWifi, didReboot) = updatedCumulatives(
            state: state, reading: reading
        )

        // 2. Roll the billing cycle over if the previous one has ended (or open
        //    the first cycle). Baseline is the cumulative total at cycle start.
        let didRollover = advanceCycleIfNeeded(
            state: &state,
            now: now,
            cumulativeCellular: cumulativeCellular,
            cumulativeWifi: cumulativeWifi
        )

        // 3. Append the snapshot.
        let snapshot = Snapshot(
            timestamp: now,
            rawCellular: reading.cellular,
            rawWifi: reading.wifi,
            cumulativeCellular: cumulativeCellular,
            cumulativeWifi: cumulativeWifi
        )
        state.snapshots.append(snapshot)
        pruneSnapshots(&state)

        // 4. Evaluate threshold alerts on the freshly-updated usage.
        let pending = evaluateAlerts(state: &state, now: now)

        store.save(state)

        return SampleResult(
            snapshot: snapshot,
            didReboot: didReboot,
            didRolloverCycle: didRollover,
            pendingAlerts: pending
        )
    }

    /// Brings the open cycle back in line with the plan's billing window without
    /// reading the counter. Call this whenever the plan changes: `sample()` would
    /// do it too, but it needs a counter read and only runs on a foreground or a
    /// widget refresh, and until then the dashboard would show one window while
    /// "days left" showed another. Returns whether the cycle moved.
    @discardableResult
    public func reconcileCycleWindow(now: Date = Date()) -> Bool {
        var state = store.load()
        guard let current = state.currentCycle, now < current.end else { return false }
        let moved = Self.redateOpenCycle(&state, to: planBounds(for: state, now: now), current: current)
        if moved { store.save(state) }
        return moved
    }

    // MARK: - Steps

    private func updatedCumulatives(
        state: AppState, reading: CounterReading
    ) -> (cellular: DataSize, wifi: DataSize, didReboot: Bool) {
        guard let last = state.latestSnapshot else {
            // First sample ever: start counting from zero (no pre-install usage).
            return (.zero, .zero, false)
        }
        let cell = RebootAdjuster.delta(previousRaw: last.rawCellular, currentRaw: reading.cellular)
        let wifi = RebootAdjuster.delta(previousRaw: last.rawWifi, currentRaw: reading.wifi)
        return (
            last.cumulativeCellular + cell.delta,
            last.cumulativeWifi + wifi.delta,
            cell.didReboot || wifi.didReboot
        )
    }

    /// Ensures `currentCycle` exists, matches the plan's billing window and
    /// contains `now`. Closes a finished cycle (recording its total) and opens a
    /// new one rebased on the current cumulative. Returns whether a
    /// rollover/open occurred.
    private func advanceCycleIfNeeded(
        state: inout AppState,
        now: Date,
        cumulativeCellular: DataSize,
        cumulativeWifi: DataSize
    ) -> Bool {
        let bounds = planBounds(for: state, now: now)

        // Still inside the open cycle: nothing to close, but the plan's reset
        // day may have moved the window under it — see `redateOpenCycle`.
        if let current = state.currentCycle, now < current.end {
            return Self.redateOpenCycle(&state, to: bounds, current: current)
        }

        if let current = state.currentCycle {
            // Close the finished cycle. Usage between its end and this sample is
            // attributed to the old cycle (accepted §7 inaccuracy). Any manual
            // calibration is folded into the final total here; the new cycle
            // starts uncalibrated because the carrier's counter resets too.
            var closed = current
            closed.totalCellular = closed.calibratedUsage(
                measured: cumulativeCellular.subtractingSaturating(current.baselineCumulativeCellular))
            closed.capGBAtClose = state.plan.capGB
            state.closedCycles.append(closed)
        }

        // Open a new cycle rebased here (or the first cycle on a fresh install).
        // The baseline is the cumulative *now* rather than at the window's start,
        // to match the total just recorded above: everything up to this instant
        // has been billed to the cycle that closed, so counting any of it again
        // here would double it. `planBounds` is re-read because the cycle that
        // just closed raises the floor the new window may start at.
        state.currentCycle = Cycle(
            start: planBounds(for: state, now: now).start,
            end: bounds.end,
            baselineCumulativeCellular: cumulativeCellular,
            baselineCumulativeWifi: cumulativeWifi
        )
        return true
    }

    /// The billing window for `now`, held clear of the last closed cycle so the
    /// two can't overlap.
    private func planBounds(for state: AppState, now: Date) -> (start: Date, end: Date) {
        calendar.cycleBounds(
            containing: now,
            resetDay: state.plan.cycleResetDay,
            notBefore: state.closedCycles.last?.end
        )
    }

    /// Moves an open cycle onto `bounds` when the plan's reset day has been
    /// changed under it. Returns whether anything moved.
    ///
    /// Without this the cycle kept its original window until `now` passed the
    /// *old* boundary, and the rollover then opened a cycle starting weeks
    /// earlier while rebasing the baseline to the current counter — so usage
    /// inside the new window but before that instant vanished from the headline
    /// figure even though the daily and cumulative charts, which go by date
    /// range, still showed it. Correcting the reset day is a correction to
    /// *when* the boundary falls, so the cycle is re-dated in place and the
    /// usage counted so far is kept.
    private static func redateOpenCycle(
        _ state: inout AppState,
        to bounds: (start: Date, end: Date),
        current: Cycle
    ) -> Bool {
        guard bounds.start != current.start || bounds.end != current.end else { return false }

        var moved = current
        moved.start = bounds.start
        moved.end = bounds.end

        if bounds.start != current.start {
            // The window now opens at a different instant, so re-anchor the
            // baseline to the counter as it stood then. When the snapshot
            // history doesn't reach back that far the existing baseline is the
            // best available anchor — keeping it can only under-count slightly,
            // whereas rebasing to "now" would drop the usage outright.
            if let anchor = state.cumulatives(asOf: bounds.start) {
                moved.baselineCumulativeCellular = anchor.cellular
                moved.baselineCumulativeWifi = anchor.wifi
            }
            // A calibration describes the carrier's figure for the *old* window,
            // so it means nothing against the new one. Dropping it leaves the
            // measured usage standing; the user can recalibrate.
            moved.manualAdjustmentCellular = nil
        }

        state.currentCycle = moved
        return true
    }

    private func evaluateAlerts(state: inout AppState, now: Date) -> [PendingAlert] {
        guard let cycle = state.currentCycle, let latest = state.snapshots.last else { return [] }
        let measured = latest.cumulativeCellular.subtractingSaturating(cycle.baselineCumulativeCellular)
        let used = cycle.calibratedUsage(measured: measured)
        let fraction = state.plan.cap.bytes == 0 ? 0 : Double(used.bytes) / Double(state.plan.cap.bytes)

        let result = alertEvaluator.evaluate(
            fractionUsed: fraction,
            thresholds: state.plan.alertThresholds,
            cycleID: cycle.id,
            state: state.alertState
        )
        state.alertState = result.state
        return result.alerts
    }

    private func pruneSnapshots(_ state: inout AppState) {
        let overflow = state.snapshots.count - snapshotRetentionLimit
        guard overflow > 0 else { return }
        // Keep the most recent; the oldest are already reflected in closed-cycle
        // totals and (mostly) past the current daily view.
        state.snapshots.removeFirst(overflow)
    }
}
