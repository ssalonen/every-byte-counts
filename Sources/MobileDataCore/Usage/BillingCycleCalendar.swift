import Foundation

/// Computes billing-cycle boundaries from a monthly reset day (design §2).
///
/// The reset day can exceed the length of a given month (e.g. 31 in February); in
/// that case it is clamped to that month's last day, so a "31st" plan resets on
/// the 28th/29th of February and the 30th of April.
public struct BillingCycleCalendar {
    public let calendar: Calendar

    public init(calendar: Calendar = Calendar(identifier: .gregorian)) {
        self.calendar = calendar
    }

    /// The reset instant (start of day) for `resetDay` within the month that
    /// `date` falls in, clamped to the month length.
    private func resetInstant(inMonthOf date: Date, resetDay: Int) -> Date {
        let comps = calendar.dateComponents([.year, .month], from: date)
        let monthStart = calendar.date(from: comps)!
        let range = calendar.range(of: .day, in: .month, for: monthStart)!
        let day = min(resetDay, range.upperBound - 1)
        return calendar.date(byAdding: .day, value: day - 1, to: monthStart)!
    }

    /// Returns the half-open `[start, end)` interval of the billing cycle that
    /// contains `date`.
    public func cycleBounds(containing date: Date, resetDay: Int) -> (start: Date, end: Date) {
        let thisMonthReset = resetInstant(inMonthOf: date, resetDay: resetDay)

        let start: Date
        if date >= thisMonthReset {
            start = thisMonthReset
        } else {
            // We're before this month's reset, so the cycle began last month.
            let prevMonth = calendar.date(byAdding: .month, value: -1, to: date)!
            start = resetInstant(inMonthOf: prevMonth, resetDay: resetDay)
        }

        let nextMonth = calendar.date(byAdding: .month, value: 1, to: start)!
        let end = resetInstant(inMonthOf: nextMonth, resetDay: resetDay)
        return (start, end)
    }

    /// `cycleBounds(containing:resetDay:)` with the start held at or after
    /// `notBefore` — the instant the previous cycle ended.
    ///
    /// Cycles must never overlap: the same traffic would otherwise be billed to
    /// two of them. Changing the reset day can move a window back over a cycle
    /// that has already closed, and clamping here keeps the current cycle to the
    /// part that is genuinely still open. `notBefore` is ignored when it doesn't
    /// fall inside the window, so a normal boundary is left exactly as computed.
    public func cycleBounds(containing date: Date, resetDay: Int, notBefore: Date?) -> (start: Date, end: Date) {
        var bounds = cycleBounds(containing: date, resetDay: resetDay)
        if let notBefore, notBefore > bounds.start, notBefore < bounds.end {
            bounds.start = notBefore
        }
        return bounds
    }

    /// Whole days remaining in the cycle containing `date`, counting the current
    /// day as remaining (always at least 1).
    public func daysRemaining(in date: Date, resetDay: Int) -> Int {
        daysRemaining(in: date, cycleEnd: cycleBounds(containing: date, resetDay: resetDay).end)
    }

    /// Whole days elapsed in the cycle so far, counting the current day (≥ 1).
    public func daysElapsed(in date: Date, resetDay: Int) -> Int {
        daysElapsed(in: date, cycleStart: cycleBounds(containing: date, resetDay: resetDay).start)
    }

    /// Whole days from `date` to `cycleEnd`, counting the current day (≥ 1).
    ///
    /// Takes the boundary rather than a reset day so callers can pass the window
    /// they are actually reporting — the stored cycle can legitimately differ
    /// from the one the reset day implies (a cycle that has been re-dated, or
    /// clamped so it doesn't overlap the previous one), and "days left" must
    /// describe the same window as the rest of the figures.
    public func daysRemaining(in date: Date, cycleEnd: Date) -> Int {
        let startOfToday = calendar.startOfDay(for: date)
        let startOfEnd = calendar.startOfDay(for: cycleEnd)
        let days = calendar.dateComponents([.day], from: startOfToday, to: startOfEnd).day ?? 0
        return max(1, days)
    }

    /// Whole days from `cycleStart` to `date`, counting the current day (≥ 1).
    public func daysElapsed(in date: Date, cycleStart: Date) -> Int {
        let startOfStart = calendar.startOfDay(for: cycleStart)
        let startOfToday = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: startOfStart, to: startOfToday).day ?? 0
        return max(1, days + 1)
    }
}
