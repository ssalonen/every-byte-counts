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
        let bounds: (start: Date, end: Date)
        if let cycle = state.currentCycle, cycle.contains(now) {
            bounds = (cycle.start, cycle.end)
        } else {
            bounds = calendar.cycleBounds(containing: now, resetDay: plan.cycleResetDay)
        }

        // Used = latest cumulative minus the cycle baseline. If we somehow have no
        // baseline yet (no sample taken this cycle), usage is zero.
        let used: DataSize
        if let cycle = state.currentCycle,
           let latest = state.latestSnapshot,
           cycle.contains(now) {
            used = latest.cumulativeCellular.subtractingSaturating(cycle.baselineCumulativeCellular)
        } else {
            used = .zero
        }

        let cap = plan.cap
        let remaining = cap.subtractingSaturating(used)
        let fraction = cap.bytes == 0 ? 0 : Double(used.bytes) / Double(cap.bytes)

        return UsageSummary(
            used: used,
            cap: cap,
            remaining: remaining,
            fractionUsed: fraction,
            daysRemaining: calendar.daysRemaining(in: now, resetDay: plan.cycleResetDay),
            daysElapsed: calendar.daysElapsed(in: now, resetDay: plan.cycleResetDay),
            cycleStart: bounds.start,
            cycleEnd: bounds.end
        )
    }
}
