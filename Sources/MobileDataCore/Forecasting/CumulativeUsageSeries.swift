import Foundation

/// One point on the cumulative-usage ("burn-up") chart.
public struct CumulativePoint: Equatable, Codable, Sendable, Identifiable {
    /// The day the point sits on, normalised like `DailyTotal.date`.
    public var date: Date
    /// Cumulative cellular usage in GB at that day.
    public var gigabytes: Double

    public var id: Date { date }

    public init(date: Date, gigabytes: Double) {
        self.date = date
        self.gigabytes = gigabytes
    }
}

/// The cumulative view of the current cycle (design §2): usage accumulated
/// day by day, plus the forecast projection continued to cycle end so the
/// chart shows *where the cycle is heading* against the cap.
///
/// `actual` runs from cycle start through the last recorded day; `projected`
/// continues from the end of `actual` to the cycle end, landing on
/// `Forecast.projectedTotalGB`. The two share their junction point so a chart
/// can draw them as one continuous path with two styles.
public struct CumulativeUsageSeries: Equatable, Sendable {
    public var actual: [CumulativePoint]
    public var projected: [CumulativePoint]
    /// The quota, for the cap line.
    public var capGB: Double
    /// Where the projection lands relative to the cap, for styling.
    public var status: ForecastStatus

    public init(actual: [CumulativePoint], projected: [CumulativePoint], capGB: Double, status: ForecastStatus) {
        self.actual = actual
        self.projected = projected
        self.capGB = capGB
        self.status = status
    }

    public init(report: UsageReport) {
        self.init(dailyTotals: report.dailyTotals, summary: report.summary, forecast: report.forecast)
    }

    public init(dailyTotals: [DailyTotal], summary: UsageSummary, forecast: Forecast) {
        let ordered = dailyTotals.sorted { $0.date < $1.date }

        var running = 0.0
        var actual: [CumulativePoint] = ordered.map { day in
            running += day.cellular.gigabytes
            return CumulativePoint(date: day.date, gigabytes: running)
        }

        // Anchor the line at the origin so the accumulation visibly starts
        // from zero — unless the first recorded day *is* the cycle start.
        if let first = actual.first, first.date > summary.cycleStart {
            actual.insert(CumulativePoint(date: summary.cycleStart, gigabytes: 0), at: 0)
        } else if actual.isEmpty, summary.used.gigabytes > 0 {
            // No per-day attribution yet (e.g. first day of tracking) but a
            // total exists — still give the projection a starting point.
            actual = [CumulativePoint(date: summary.cycleStart, gigabytes: summary.used.gigabytes)]
        }

        let projectionStart = actual.last ?? CumulativePoint(date: summary.cycleStart, gigabytes: 0)
        var projected: [CumulativePoint] = []
        if summary.cycleEnd > projectionStart.date {
            projected = [
                projectionStart,
                CumulativePoint(date: summary.cycleEnd, gigabytes: forecast.projectedTotalGB)
            ]
        }

        self.init(actual: actual, projected: projected, capGB: summary.cap.gigabytes, status: forecast.status)
    }
}
