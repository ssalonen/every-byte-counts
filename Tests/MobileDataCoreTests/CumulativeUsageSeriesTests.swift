import XCTest
@testable import MobileDataCore

final class CumulativeUsageSeriesTests: XCTestCase {
    private let cycleStart = TestDates.date(2026, 3, 1, 0, 0)
    private let cycleEnd = TestDates.date(2026, 4, 1, 0, 0)

    private func summary(usedGB: Double, capGB: Double = 20) -> UsageSummary {
        UsageSummary(
            used: DataSize(gigabytes: usedGB),
            cap: DataSize(gigabytes: capGB),
            remaining: DataSize(gigabytes: max(0, capGB - usedGB)),
            fractionUsed: usedGB / capGB,
            daysRemaining: 10,
            daysElapsed: 21,
            cycleStart: cycleStart,
            cycleEnd: cycleEnd
        )
    }

    private func forecast(projectedGB: Double, status: ForecastStatus = .safe) -> Forecast {
        Forecast(
            remainingDailyBudgetGB: 1,
            projectedTotalGB: projectedGB,
            projectedExcessGB: 0,
            status: status,
            weightedDailyAverageGB: 1,
            overageCostEUR: 0,
            overageBasis: ""
        )
    }

    private func daily(_ values: [Double], startingDay: Int) -> [DailyTotal] {
        values.enumerated().map { i, gb in
            DailyTotal(date: TestDates.date(2026, 3, startingDay + i, 0, 0), cellular: DataSize(gigabytes: gb))
        }
    }

    func testAccumulatesDailyTotalsInDateOrder() {
        // Deliberately unsorted input: day 3 (2 GB), day 1 (1 GB), day 2 (0.5 GB).
        let totals = [
            DailyTotal(date: TestDates.date(2026, 3, 3, 0, 0), cellular: DataSize(gigabytes: 2)),
            DailyTotal(date: TestDates.date(2026, 3, 1, 0, 0), cellular: DataSize(gigabytes: 1)),
            DailyTotal(date: TestDates.date(2026, 3, 2, 0, 0), cellular: DataSize(gigabytes: 0.5))
        ]
        let series = CumulativeUsageSeries(dailyTotals: totals, summary: summary(usedGB: 3.5), forecast: forecast(projectedGB: 5))

        XCTAssertEqual(series.actual.map(\.gigabytes), [1, 1.5, 3.5])
        XCTAssertEqual(series.actual.map(\.date), [
            TestDates.date(2026, 3, 1, 0, 0),
            TestDates.date(2026, 3, 2, 0, 0),
            TestDates.date(2026, 3, 3, 0, 0)
        ])
    }

    func testInsertsZeroAnchorWhenFirstDayIsAfterCycleStart() {
        // First recorded day is the 5th; the line must still rise from zero at
        // the cycle start on the 1st.
        let series = CumulativeUsageSeries(
            dailyTotals: daily([2, 1], startingDay: 5),
            summary: summary(usedGB: 3),
            forecast: forecast(projectedGB: 6)
        )
        XCTAssertEqual(series.actual.first, CumulativePoint(date: cycleStart, gigabytes: 0))
        XCTAssertEqual(series.actual.map(\.gigabytes), [0, 2, 3])
    }

    func testNoZeroAnchorWhenFirstDayIsCycleStart() {
        let series = CumulativeUsageSeries(
            dailyTotals: daily([2], startingDay: 1),
            summary: summary(usedGB: 2),
            forecast: forecast(projectedGB: 6)
        )
        XCTAssertEqual(series.actual, [CumulativePoint(date: cycleStart, gigabytes: 2)])
    }

    func testProjectionRunsFromLastActualPointToCycleEnd() {
        let series = CumulativeUsageSeries(
            dailyTotals: daily([2, 1], startingDay: 1),
            summary: summary(usedGB: 3),
            forecast: forecast(projectedGB: 12, status: .atRisk)
        )
        // Shares its first point with the end of `actual` so a chart can draw
        // one continuous path.
        XCTAssertEqual(series.projected.first, series.actual.last)
        XCTAssertEqual(series.projected.last, CumulativePoint(date: cycleEnd, gigabytes: 12))
        XCTAssertEqual(series.status, .atRisk)
        XCTAssertEqual(series.capGB, 20, accuracy: 1e-9)
    }

    func testEmptyDailyTotalsWithUsageSynthesisesStartPoint() {
        // A total exists but no per-day attribution yet: the projection still
        // needs somewhere to start.
        let series = CumulativeUsageSeries(dailyTotals: [], summary: summary(usedGB: 4), forecast: forecast(projectedGB: 10))
        XCTAssertEqual(series.actual, [CumulativePoint(date: cycleStart, gigabytes: 4)])
        XCTAssertEqual(series.projected, [
            CumulativePoint(date: cycleStart, gigabytes: 4),
            CumulativePoint(date: cycleEnd, gigabytes: 10)
        ])
    }

    func testEmptyDailyTotalsAndZeroUsageProjectsFromZero() {
        let series = CumulativeUsageSeries(dailyTotals: [], summary: summary(usedGB: 0), forecast: forecast(projectedGB: 0))
        XCTAssertTrue(series.actual.isEmpty)
        XCTAssertEqual(series.projected, [
            CumulativePoint(date: cycleStart, gigabytes: 0),
            CumulativePoint(date: cycleEnd, gigabytes: 0)
        ])
    }

    func testNoProjectionWhenLastDayIsAtOrPastCycleEnd() {
        // Last recorded day sits on the cycle-end instant (degenerate data):
        // nothing left to project.
        let totals = [DailyTotal(date: cycleEnd, cellular: DataSize(gigabytes: 1))]
        let series = CumulativeUsageSeries(dailyTotals: totals, summary: summary(usedGB: 1), forecast: forecast(projectedGB: 1))
        XCTAssertTrue(series.projected.isEmpty)
    }

    func testInitFromReportUsesItsComponents() {
        let report = UsageReport(
            summary: summary(usedGB: 3),
            forecast: forecast(projectedGB: 9, status: .over),
            dailyTotals: daily([1, 2], startingDay: 1),
            plan: .default
        )
        let series = CumulativeUsageSeries(report: report)
        XCTAssertEqual(series.actual.map(\.gigabytes), [1, 3])
        XCTAssertEqual(series.projected.last?.gigabytes ?? -1, 9, accuracy: 1e-9)
        XCTAssertEqual(series.status, .over)
    }
}
