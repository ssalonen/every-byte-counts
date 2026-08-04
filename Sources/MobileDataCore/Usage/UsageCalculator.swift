import Foundation

/// Derives the dashboard `UsageSummary` from persisted state (design §2). Usage
/// in the current cycle is `currentCumulative - cycleBaseline`, so a reset is
/// just a new baseline — the underlying counter is never zeroed.
public struct UsageCalculator {
    public let calendar: BillingCycleCalendar

    public init(calendar: BillingCycleCalendar = BillingCycleCalendar()) {
        self.calendar = calendar
    }

    public func summary(for state: AppState, asOf now: Date = Date()) -> UsageSummary {
        let plan = state.plan

        // Used = latest cumulative minus the cycle baseline, plus any manual
        // calibration for this cycle (mid-cycle installs under-count until the
        // user aligns the figure with the carrier's).
        let bounds: (start: Date, end: Date)
        let used: DataSize
        if let cycle = state.currentCycle, cycle.contains(now) {
            bounds = (cycle.start, cycle.end)
            let measured = (state.latestSnapshot?.cumulativeCellular ?? .zero)
                .subtractingSaturating(cycle.baselineCumulativeCellular)
            used = cycle.calibratedUsage(measured: measured)
        } else {
            // No cycle yet, or the stored one has ended and no sample has rolled
            // it over. Report the window the plan implies and measure against the
            // counter as it stood when that window opened: reporting a flat zero
            // here would claim the cycle is untouched while the daily and
            // cumulative charts, which go by date range, showed the usage.
            bounds = calendar.cycleBounds(
                containing: now,
                resetDay: plan.cycleResetDay,
                notBefore: state.closedCycles.last?.end
            )
            if let baseline = state.cumulatives(asOf: bounds.start)?.cellular,
               let latest = state.latestSnapshot {
                used = latest.cumulativeCellular.subtractingSaturating(baseline)
            } else {
                // Nothing sampled in this window — genuinely nothing to report.
                used = .zero
            }
        }

        let cap = plan.cap
        let remaining = cap.subtractingSaturating(used)
        let fraction = cap.bytes == 0 ? 0 : Double(used.bytes) / Double(cap.bytes)

        return UsageSummary(
            used: used,
            cap: cap,
            remaining: remaining,
            fractionUsed: fraction,
            // Derived from the window reported above, not from the reset day, so
            // "days left" always describes the cycle the other figures describe.
            daysRemaining: calendar.daysRemaining(in: now, cycleEnd: bounds.end),
            daysElapsed: calendar.daysElapsed(in: now, cycleStart: bounds.start),
            cycleStart: bounds.start,
            cycleEnd: bounds.end
        )
    }
}
