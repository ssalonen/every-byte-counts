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

    /// Ensures `currentCycle` exists and contains `now`. Closes a finished cycle
    /// (recording its total) and opens a new one rebased on the current
    /// cumulative. Returns whether a rollover/open occurred.
    private func advanceCycleIfNeeded(
        state: inout AppState,
        now: Date,
        cumulativeCellular: DataSize,
        cumulativeWifi: DataSize
    ) -> Bool {
        let bounds = calendar.cycleBounds(containing: now, resetDay: state.plan.cycleResetDay)

        if let current = state.currentCycle {
            guard now >= current.end else { return false } // still inside the cycle

            // Close the finished cycle. Usage between its end and this sample is
            // attributed to the old cycle (accepted §7 inaccuracy).
            var closed = current
            closed.totalCellular = cumulativeCellular.subtractingSaturating(current.baselineCumulativeCellular)
            closed.capGBAtClose = state.plan.capGB
            state.closedCycles.append(closed)
        }

        // Open a new cycle rebased here (or the first cycle on a fresh install).
        state.currentCycle = Cycle(
            start: bounds.start,
            end: bounds.end,
            baselineCumulativeCellular: cumulativeCellular,
            baselineCumulativeWifi: cumulativeWifi
        )
        return true
    }

    private func evaluateAlerts(state: inout AppState, now: Date) -> [PendingAlert] {
        guard let cycle = state.currentCycle, let latest = state.snapshots.last else { return [] }
        let used = latest.cumulativeCellular.subtractingSaturating(cycle.baselineCumulativeCellular)
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
