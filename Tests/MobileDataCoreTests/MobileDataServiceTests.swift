import XCTest
@testable import MobileDataCore

final class MobileDataServiceTests: XCTestCase {
    private func makeService(_ reader: MockCounterReader, store: InMemoryDataStore) -> MobileDataService {
        MobileDataService(
            store: store,
            reader: reader,
            calendar: BillingCycleCalendar(calendar: TestDates.calendar),
            aggregator: DailyAggregator(calendar: TestDates.calendar)
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

    func testReportExposesUsageForCurrentDay() {
        let store = InMemoryDataStore(AppState(plan: PlanConfig(capGB: 20, cycleResetDay: 1)))
        let reader = MockCounterReader(cellular: 0)
        let service = makeService(reader, store: store)

        // 3 GB lands on Mar 4 (the interval ends exactly at midnight), then
        // 1 GB entirely within Mar 5.
        service.sample(now: TestDates.date(2026, 3, 4, 12))
        reader.add(cellular: 3 * GB)
        service.sample(now: TestDates.date(2026, 3, 5, 0, 0))
        reader.add(cellular: 1 * GB)
        service.sample(now: TestDates.date(2026, 3, 5, 12))

        let report = service.report(asOf: TestDates.date(2026, 3, 5, 18))
        XCTAssertEqual(report.usedToday.bytes, 1 * GB)   // only today's slice
        XCTAssertEqual(report.summary.used.bytes, 4 * GB) // cycle total unchanged
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

    func testReportOnFreshStoreIsAllZerosNotACrash() {
        // Before any sample, report() must return a sane zeroed snapshot.
        let service = makeService(MockCounterReader(), store: InMemoryDataStore(
            AppState(plan: PlanConfig(capGB: 20, cycleResetDay: 1))))
        let report = service.report(asOf: TestDates.date(2026, 3, 15, 12))

        XCTAssertEqual(report.summary.used, .zero)
        XCTAssertEqual(report.usedToday, .zero)
        XCTAssertEqual(report.summary.remaining.bytes, 20_000_000_000)
        XCTAssertTrue(report.dailyTotals.isEmpty)
        XCTAssertEqual(report.forecast.status, .safe)
        XCTAssertEqual(report.forecast.projectedExcessGB, 0)
    }

    func testCycleHistoryEmptyUntilACycleCloses() {
        let store = InMemoryDataStore(AppState(plan: PlanConfig(capGB: 20, cycleResetDay: 1)))
        let service = makeService(MockCounterReader(), store: store)
        service.sample(now: TestDates.date(2026, 3, 1, 9))   // opens, never closes
        XCTAssertTrue(service.cycleHistory().isEmpty)
    }

    func testCurrentStateExposesPlan() {
        let store = InMemoryDataStore(AppState(plan: PlanConfig(capGB: 33, cycleResetDay: 1)))
        let service = makeService(MockCounterReader(), store: store)
        XCTAssertEqual(service.currentState().plan.capGB, 33)
    }

    #if os(macOS)
    func testLiveFactoryBuildsUsableServiceWhenContainerResolves() {
        // On macOS the App Group container resolves *without* an entitlement
        // (unlike iOS, where it returns nil without one), so the live factory
        // returns a usable service here — which exercises the real wiring path.
        let service = MobileDataService.live(appGroupIdentifier: AppConstants.appGroupIdentifier)
        XCTAssertNotNil(service)
        XCTAssertNotNil(service?.report())   // load → summarise → forecast must work
    }
    #endif

    // MARK: - Calibration (mid-cycle install)

    func testCalibrationAlignsMidCycleInstallWithCarrierFigure() {
        let store = InMemoryDataStore(AppState(plan: PlanConfig(capGB: 20, cycleResetDay: 1)))
        let reader = MockCounterReader(cellular: 0)
        let service = makeService(reader, store: store)

        // Installed Mar 10: the app has only seen 1 GB since install…
        service.sample(now: TestDates.date(2026, 3, 10, 9))
        reader.add(cellular: 1 * GB)
        service.sample(now: TestDates.date(2026, 3, 12, 9))

        // …but the carrier says 6 GB were used this cycle.
        XCTAssertTrue(service.calibrate(
            usedThisCycle: DataSize(bytes: 6 * GB), now: TestDates.date(2026, 3, 12, 10)))

        let report = service.report(asOf: TestDates.date(2026, 3, 12, 12))
        XCTAssertEqual(report.summary.used.bytes, 6 * GB)
        XCTAssertEqual(report.summary.remaining.bytes, 14 * GB)

        // New traffic keeps counting on top of the calibrated figure.
        reader.add(cellular: 2 * GB)
        service.sample(now: TestDates.date(2026, 3, 13, 9))
        XCTAssertEqual(service.report(asOf: TestDates.date(2026, 3, 13, 12)).summary.used.bytes, 8 * GB)
    }

    func testCalibrationDownwardNeverGoesNegative() {
        let store = InMemoryDataStore(AppState(plan: PlanConfig(capGB: 20, cycleResetDay: 1)))
        let reader = MockCounterReader(cellular: 0)
        let service = makeService(reader, store: store)

        service.sample(now: TestDates.date(2026, 3, 10, 9))
        reader.add(cellular: 3 * GB)
        service.sample(now: TestDates.date(2026, 3, 12, 9))

        // Carrier counts less than the app measured (e.g. zero-rated traffic).
        service.calibrate(usedThisCycle: DataSize(bytes: 1 * GB), now: TestDates.date(2026, 3, 12, 10))
        XCTAssertEqual(service.report(asOf: TestDates.date(2026, 3, 12, 12)).summary.used.bytes, 1 * GB)

        // Even calibrating to zero clamps rather than underflowing.
        service.calibrate(usedThisCycle: .zero, now: TestDates.date(2026, 3, 12, 11))
        XCTAssertEqual(service.report(asOf: TestDates.date(2026, 3, 12, 12)).summary.used, .zero)
    }

    func testCalibrationFoldsIntoClosedCycleAndDoesNotCarryOver() {
        let store = InMemoryDataStore(AppState(
            plan: PlanConfig(capGB: 10, cycleResetDay: 1, costModel: .flatRate(eurPerGB: 5))
        ))
        let reader = MockCounterReader(cellular: 0)
        let service = makeService(reader, store: store)

        service.sample(now: TestDates.date(2026, 3, 10, 9))
        reader.add(cellular: 1 * GB)
        service.calibrate(usedThisCycle: DataSize(bytes: 9 * GB), now: TestDates.date(2026, 3, 20, 9))

        // 3 GB more before the rollover sample → March closes at 9 + 3 = 12 GB,
        // 2 GB over the 10 GB cap.
        reader.add(cellular: 3 * GB)
        service.sample(now: TestDates.date(2026, 4, 2, 9))

        let history = service.cycleHistory()
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history[0].total.bytes, 12 * GB)
        XCTAssertEqual(history[0].overageGB, 2, accuracy: 1e-6)

        // April starts uncalibrated: only newly measured traffic counts.
        reader.add(cellular: 1 * GB)
        service.sample(now: TestDates.date(2026, 4, 3, 9))
        XCTAssertEqual(service.report(asOf: TestDates.date(2026, 4, 3, 12)).summary.used.bytes, 1 * GB)
    }

    func testCalibratedUsageDrivesAlerts() {
        let store = InMemoryDataStore(AppState(plan: PlanConfig(capGB: 10, cycleResetDay: 1)))
        let reader = MockCounterReader(cellular: 0)
        let service = makeService(reader, store: store)

        service.sample(now: TestDates.date(2026, 3, 10, 9))
        // Carrier says 9 GB of the 10 GB cap are already gone → the next sample
        // must fire the 50% and 80% thresholds.
        service.calibrate(usedThisCycle: DataSize(bytes: 9 * GB), now: TestDates.date(2026, 3, 10, 10))
        let result = service.sample(now: TestDates.date(2026, 3, 10, 11))
        XCTAssertEqual(result?.pendingAlerts.map(\.threshold), [0.5, 0.8])
    }

    func testCalibrateFailsWhenCounterUnreadableOnFreshInstall() {
        let store = InMemoryDataStore(AppState(plan: PlanConfig(capGB: 20, cycleResetDay: 1)))
        let reader = MockCounterReader()
        reader.shouldThrow = true
        let service = makeService(reader, store: store)
        XCTAssertFalse(service.calibrate(
            usedThisCycle: DataSize(bytes: 1 * GB), now: TestDates.date(2026, 3, 10, 9)))
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
