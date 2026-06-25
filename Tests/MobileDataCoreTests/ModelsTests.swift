import XCTest
@testable import MobileDataCore

final class ModelsTests: XCTestCase {

    // MARK: Cycle

    func testCycleContainsIsHalfOpenInterval() {
        let cycle = Cycle(
            start: TestDates.date(2026, 3, 1, 0, 0),
            end: TestDates.date(2026, 4, 1, 0, 0),
            baselineCumulativeCellular: .zero,
            baselineCumulativeWifi: .zero
        )
        XCTAssertTrue(cycle.contains(TestDates.date(2026, 3, 1, 0, 0)), "start is inclusive")
        XCTAssertTrue(cycle.contains(TestDates.date(2026, 3, 31, 23, 59)))
        XCTAssertFalse(cycle.contains(TestDates.date(2026, 4, 1, 0, 0)), "end is exclusive")
        XCTAssertFalse(cycle.contains(TestDates.date(2026, 2, 28, 0, 0)))
    }

    func testCycleIsClosedOnlyWhenTotalSet() {
        var cycle = Cycle(start: Date(), end: Date(), baselineCumulativeCellular: .zero, baselineCumulativeWifi: .zero)
        XCTAssertFalse(cycle.isClosed)
        cycle.totalCellular = DataSize(gigabytes: 5)
        XCTAssertTrue(cycle.isClosed)
    }

    // MARK: DailyTotal

    func testDailyTotalIdentifiedByDate() {
        let day = TestDates.date(2026, 3, 10, 0, 0)
        XCTAssertEqual(DailyTotal(date: day, cellular: .zero).id, day)
    }

    // MARK: AlertState

    func testAlertStateEmptyHasNoFiredThresholds() {
        XCTAssertNil(AlertState.empty.cycleID)
        XCTAssertTrue(AlertState.empty.firedThresholds.isEmpty)
    }

    // MARK: Codable persistence (round-trips through the JSON store shape)

    func testAppStateRoundTripsThroughJSON() throws {
        let snapshot = Snapshot(
            timestamp: TestDates.date(2026, 3, 10, 12),
            rawCellular: DataSize(bytes: 123),
            rawWifi: DataSize(bytes: 456),
            cumulativeCellular: DataSize(bytes: 123),
            cumulativeWifi: DataSize(bytes: 456),
            attribution: "home"   // extensibility hook must survive persistence
        )
        let state = AppState(
            plan: PlanConfig(capGB: 30, cycleResetDay: 12, costModel: .stepped(blockGB: 1, eurPerBlock: 6)),
            installDate: TestDates.date(2026, 1, 1),
            snapshots: [snapshot],
            currentCycle: Cycle(start: TestDates.date(2026, 3, 1), end: TestDates.date(2026, 4, 1),
                                baselineCumulativeCellular: .zero, baselineCumulativeWifi: .zero),
            closedCycles: [],
            alertState: AlertState(cycleID: UUID(), firedThresholds: [0.5])
        )

        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(AppState.self, from: encoder.encode(state))

        XCTAssertEqual(decoded, state)
        XCTAssertEqual(decoded.snapshots.first?.attribution, "home")
        XCTAssertEqual(decoded.plan.costModel, .stepped(blockGB: 1, eurPerBlock: 6))
    }

    func testCostModelConfigCasesRoundTrip() throws {
        let encoder = JSONEncoder(), decoder = JSONDecoder()
        for model in [CostModelConfig.flatRate(eurPerGB: 5),
                      .stepped(blockGB: 2, eurPerBlock: 9),
                      .throttle] {
            let decoded = try decoder.decode(CostModelConfig.self, from: encoder.encode(model))
            XCTAssertEqual(decoded, model)
        }
    }
}
