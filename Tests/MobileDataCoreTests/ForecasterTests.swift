import XCTest
@testable import MobileDataCore

final class ForecasterTests: XCTestCase {
    private func daily(_ values: [Double], startingDay: Int = 1) -> [DailyTotal] {
        values.enumerated().map { i, gb in
            DailyTotal(date: TestDates.date(2026, 3, startingDay + i), cellular: DataSize(gigabytes: gb))
        }
    }

    func testRemainingDailyBudgetIsHeadline() {
        let f = Forecaster()
        // Used 6 of 20 GB, 7 days left → (20-6)/7 = 2.0 GB/day.
        let forecast = f.forecast(
            dailyTotals: daily([1, 1, 1, 1, 1, 1]),
            used: DataSize(gigabytes: 6),
            capGB: 20,
            daysRemaining: 7,
            costStrategy: FlatRateCostStrategy(eurPerGB: 5)
        )
        XCTAssertEqual(forecast.remainingDailyBudgetGB, 2.0, accuracy: 1e-9)
    }

    func testWeightedAverageFavoursRecentDays() {
        let f = Forecaster(decay: 0.5)
        // Low early, high recent → weighted avg pulled toward the recent 2 GB.
        let avg = f.weightedDailyAverageGB(daily([0, 0, 0, 2, 2]))
        let plainMean = 4.0 / 5.0
        XCTAssertGreaterThan(avg, plainMean)
    }

    func testStatusOverWhenProjectedToExceed() {
        let f = Forecaster()
        // 2 GB/day weighted, 10 days left, used 5 → projected 25 > 20.
        let forecast = f.forecast(
            dailyTotals: daily([2, 2, 2]),
            used: DataSize(gigabytes: 5),
            capGB: 20,
            daysRemaining: 10,
            costStrategy: FlatRateCostStrategy(eurPerGB: 4)
        )
        XCTAssertEqual(forecast.status, .over)
        XCTAssertGreaterThan(forecast.projectedExcessGB, 0)
        // Overage cost flows through the strategy.
        XCTAssertEqual(forecast.overageCostEUR, forecast.projectedExcessGB * 4, accuracy: 1e-6)
    }

    func testStatusSafeWhenWellUnder() {
        let f = Forecaster()
        let forecast = f.forecast(
            dailyTotals: daily([0.1, 0.1, 0.1]),
            used: DataSize(gigabytes: 1),
            capGB: 50,
            daysRemaining: 10,
            costStrategy: FlatRateCostStrategy(eurPerGB: 5)
        )
        XCTAssertEqual(forecast.status, .safe)
        XCTAssertEqual(forecast.overageCostEUR, 0)
    }

    func testEmptyHistoryGivesZeroAverage() {
        let f = Forecaster()
        XCTAssertEqual(f.weightedDailyAverageGB([]), 0)
    }
}
