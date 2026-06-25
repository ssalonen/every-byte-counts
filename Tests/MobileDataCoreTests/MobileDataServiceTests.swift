import XCTest
@testable import MobileDataCore

final class MobileDataServiceTests: XCTestCase {
    private func makeService(_ reader: MockCounterReader, store: InMemoryDataStore) -> MobileDataService {
        MobileDataService(
            store: store,
            reader: reader,
            calendar: BillingCycleCalendar(calendar: TestDates.calendar)
        )
    }

    func testReportReflectsUsageAndRemaining() {
        let store = InMemoryDataStore(AppState(plan: PlanConfig(capGB: 20, cycleResetDay: 1)))
        let reader = MockCounterReader(cellular: 0)
        let service = makeService(reader, store: store)

        service.sample(now: TestDates.date(2026, 3, 1, 9))
        reader.add(cellular: 5 * GB)
        service.sample(now: TestDates.date(2026, 3, 5, 9))

        let report = service.report(asOf: TestDates.date(2026, 3, 5, 12))
        XCTAssertEqual(report.summary.used.bytes, 5 * GB)
        XCTAssertEqual(report.summary.remaining.bytes, 15 * GB)
        XCTAssertEqual(report.summary.fractionUsed, 0.25, accuracy: 1e-9)
        XCTAssertFalse(report.dailyTotals.isEmpty)
    }

    func testCycleHistoryExposesOverageAndCost() {
        let store = InMemoryDataStore(AppState(
            plan: PlanConfig(capGB: 10, cycleResetDay: 1, costModel: .flatRate(eurPerGB: 5))
        ))
        let reader = MockCounterReader(cellular: 0)
        let service = makeService(reader, store: store)

        service.sample(now: TestDates.date(2026, 3, 5, 9))   // open March
        reader.add(cellular: 13 * GB)                        // 13 GB → 3 GB over the 10 GB cap
        service.sample(now: TestDates.date(2026, 4, 2, 9))   // roll into April, close March

        let history = service.cycleHistory()
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history[0].total.bytes, 13 * GB)
        XCTAssertEqual(history[0].overageGB, 3, accuracy: 1e-6)
        XCTAssertEqual(history[0].estimatedCostEUR, 15, accuracy: 1e-6) // 3 GB × €5
    }

    func testUpdatePlanPersists() {
        let store = InMemoryDataStore()
        let service = makeService(MockCounterReader(), store: store)
        service.updatePlan { $0.capGB = 50 }
        XCTAssertEqual(store.load().plan.capGB, 50)
    }

    func testForecastIncludedInReport() {
        let store = InMemoryDataStore(AppState(plan: PlanConfig(capGB: 20, cycleResetDay: 1)))
        let reader = MockCounterReader(cellular: 0)
        let service = makeService(reader, store: store)

        service.sample(now: TestDates.date(2026, 3, 1, 9))
        reader.add(cellular: 2 * GB)
        service.sample(now: TestDates.date(2026, 3, 2, 9))

        let report = service.report(asOf: TestDates.date(2026, 3, 2, 12))
        XCTAssertGreaterThan(report.forecast.remainingDailyBudgetGB, 0)
    }
}
