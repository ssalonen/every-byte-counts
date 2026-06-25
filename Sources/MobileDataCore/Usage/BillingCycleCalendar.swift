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

    /// Whole days remaining in the cycle containing `date`, counting the current
    /// day as remaining (always at least 1).
    public func daysRemaining(in date: Date, resetDay: Int) -> Int {
        let (_, end) = cycleBounds(containing: date, resetDay: resetDay)
        let startOfToday = calendar.startOfDay(for: date)
        let startOfEnd = calendar.startOfDay(for: end)
        let days = calendar.dateComponents([.day], from: startOfToday, to: startOfEnd).day ?? 0
        return max(1, days)
    }

    /// Whole days elapsed in the cycle so far, counting the current day (≥ 1).
    public func daysElapsed(in date: Date, resetDay: Int) -> Int {
        let (start, _) = cycleBounds(containing: date, resetDay: resetDay)
        let startOfStart = calendar.startOfDay(for: start)
        let startOfToday = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: startOfStart, to: startOfToday).day ?? 0
        return max(1, days + 1)
    }
}
