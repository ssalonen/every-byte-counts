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
        // The budget is purely (cap - used) / daysRemaining and must NOT depend
        // on usage history — pass an empty history to prove that.
        // (20 - 6) / 7 = 2.0 GB/day.
        let forecast = f.forecast(
            dailyTotals: [],
            used: DataSize(gigabytes: 6),
            capGB: 20,
            daysRemaining: 7,
            costStrategy: FlatRateCostStrategy(eurPerGB: 5)
        )
        XCTAssertEqual(forecast.remainingDailyBudgetGB, 2.0, accuracy: 1e-9)
    }

    func testRemainingBudgetIsZeroWhenAlreadyOverCap() {
        let f = Forecaster()
        // Used 25 of a 20 GB cap → no budget left; never negative.
        let forecast = f.forecast(
            dailyTotals: [], used: DataSize(gigabytes: 25),
            capGB: 20, daysRemaining: 5, costStrategy: FlatRateCostStrategy(eurPerGB: 5)
        )
        XCTAssertEqual(forecast.remainingDailyBudgetGB, 0)
    }

    func testWeightedAverageEqualsExactExpectedValue() {
        let f = Forecaster(decay: 0.5)
        // daily [0,0,0,2,2], weights newest→oldest = 1, .5, .25, .125, .0625.
        // weightedSum = 2*1 + 2*0.5 = 3 ; weightTotal = 1.9375 → 3/1.9375.
        let avg = f.weightedDailyAverageGB(daily([0, 0, 0, 2, 2]))
        XCTAssertEqual(avg, 3.0 / 1.9375, accuracy: 1e-9)
        // Sanity: a recency-weighted mean must sit above the plain mean (0.8).
        XCTAssertGreaterThan(avg, 4.0 / 5.0)
    }

    func testEqualDailyUsageWeightsToThatExactValue() {
        // When every day is identical, recency weighting is irrelevant and the
        // weighted average must equal that value exactly.
        let f = Forecaster(decay: 0.3)
        XCTAssertEqual(f.weightedDailyAverageGB(daily([1.5, 1.5, 1.5])), 1.5, accuracy: 1e-9)
    }

    func testStatusOverWithConcreteProjectionAndCost() {
        let f = Forecaster()
        // Equal days → weighted avg = 2 GB/day exactly. used 5, 10 days left:
        // projected = 5 + 2*10 = 25 ; excess = 25 - 20 = 5 ; cost = 5 * €4 = €20.
        let forecast = f.forecast(
            dailyTotals: daily([2, 2, 2]),
            used: DataSize(gigabytes: 5),
            capGB: 20,
            daysRemaining: 10,
            costStrategy: FlatRateCostStrategy(eurPerGB: 4)
        )
        XCTAssertEqual(forecast.status, .over)
        XCTAssertEqual(forecast.projectedTotalGB, 25, accuracy: 1e-9)
        XCTAssertEqual(forecast.projectedExcessGB, 5, accuracy: 1e-9)
        XCTAssertEqual(forecast.overageCostEUR, 20, accuracy: 1e-9)
        XCTAssertFalse(forecast.overageBasis.isEmpty)
    }

    func testStatusAtRiskInAmberBandBelowCap() {
        // Projected 18 of 20 (90%) is over the 0.85 at-risk fraction but under
        // the cap → amber "at risk", and no overage cost.
        let f = Forecaster(atRiskFraction: 0.85)
        let forecast = f.forecast(
            dailyTotals: daily([2, 2]),   // weighted avg 2
            used: DataSize(gigabytes: 8),
            capGB: 20,
            daysRemaining: 5,             // projected 8 + 2*5 = 18
            costStrategy: FlatRateCostStrategy(eurPerGB: 5)
        )
        XCTAssertEqual(forecast.projectedTotalGB, 18, accuracy: 1e-9)
        XCTAssertEqual(forecast.status, .atRisk)
        XCTAssertEqual(forecast.overageCostEUR, 0)
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
