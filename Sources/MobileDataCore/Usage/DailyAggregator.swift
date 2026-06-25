import Foundation

/// Turns the snapshot stream into per-day totals (design §2/§6).
///
/// Each consecutive pair of snapshots yields a cellular/WiFi delta (from the
/// monotonic cumulative counters, so reboots are already handled). A delta that
/// straddles midnight is split across the days it covers *proportionally to
/// elapsed time*, which keeps day boundaries smooth — the §7 caveat that usage
/// spanning a boundary can't be attributed exactly is accepted here.
public struct DailyAggregator {
    public let calendar: Calendar

    public init(calendar: Calendar = Calendar(identifier: .gregorian)) {
        self.calendar = calendar
    }

    /// Daily totals for snapshots whose ending instant falls within
    /// `[range.start, range.end)`, sorted by day ascending. Days with no usage
    /// are omitted.
    public func dailyTotals(from snapshots: [Snapshot], in range: (start: Date, end: Date)? = nil) -> [DailyTotal] {
        guard snapshots.count >= 2 else { return [] }
        let ordered = snapshots.sorted { $0.timestamp < $1.timestamp }

        // Accumulate bytes per start-of-day.
        var cellularByDay: [Date: Double] = [:]
        var wifiByDay: [Date: Double] = [:]

        for i in 1..<ordered.count {
            let prev = ordered[i - 1]
            let curr = ordered[i]

            let cellularDelta = Double(curr.cumulativeCellular.subtractingSaturating(prev.cumulativeCellular).bytes)
            let wifiDelta = Double(curr.cumulativeWifi.subtractingSaturating(prev.cumulativeWifi).bytes)
            if cellularDelta == 0 && wifiDelta == 0 { continue }

            for (day, fraction) in dayFractions(from: prev.timestamp, to: curr.timestamp) {
                cellularByDay[day, default: 0] += cellularDelta * fraction
                wifiByDay[day, default: 0] += wifiDelta * fraction
            }
        }

        let totals = cellularByDay.keys.union(wifiByDay.keys).map { day in
            DailyTotal(
                date: day,
                cellular: DataSize(bytes: UInt64(max(0, cellularByDay[day] ?? 0).rounded())),
                wifi: DataSize(bytes: UInt64(max(0, wifiByDay[day] ?? 0).rounded()))
            )
        }

        let filtered: [DailyTotal]
        if let range {
            let startDay = calendar.startOfDay(for: range.start)
            filtered = totals.filter { $0.date >= startDay && $0.date < range.end }
        } else {
            filtered = totals
        }
        return filtered.sorted { $0.date < $1.date }
    }

    /// Splits the interval `[start, end)` into the start-of-day buckets it covers,
    /// returning the fraction of the interval's duration that lands in each day.
    func dayFractions(from start: Date, to end: Date) -> [(day: Date, fraction: Double)] {
        guard end > start else {
            return [(calendar.startOfDay(for: start), 1.0)]
        }
        let totalDuration = end.timeIntervalSince(start)
        var result: [(Date, Double)] = []
        var cursor = start

        while cursor < end {
            let dayStart = calendar.startOfDay(for: cursor)
            let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart)!
            let segmentEnd = min(nextDay, end)
            let fraction = segmentEnd.timeIntervalSince(cursor) / totalDuration
            result.append((dayStart, fraction))
            cursor = segmentEnd
        }
        return result
    }
}
