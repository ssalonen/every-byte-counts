import XCTest
@testable import MobileDataCore

final class DataStoreTests: XCTestCase {
    private var url: URL!

    override func setUp() {
        super.setUp()
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ebc-test-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: url)
        super.tearDown()
    }

    func testFileStoreRoundTripsState() {
        let store = FileDataStore(url: url)
        var state = AppState()
        state.plan.capGB = 42
        state.installDate = TestDates.date(2026, 1, 1)
        store.save(state)

        let reloaded = FileDataStore(url: url).load()  // fresh instance, same file
        XCTAssertEqual(reloaded.plan.capGB, 42)
        XCTAssertEqual(reloaded.installDate, TestDates.date(2026, 1, 1))
    }

    func testMissingFileReturnsFreshState() {
        let store = FileDataStore(url: url)  // file does not exist yet
        XCTAssertEqual(store.load(), AppState())
    }

    func testCorruptFileFallsBackToFreshState() throws {
        try "this is not json".data(using: .utf8)!.write(to: url)
        let store = FileDataStore(url: url)
        // Must not throw or crash on a garbage file; degrade to defaults.
        XCTAssertEqual(store.load().plan.capGB, PlanConfig.default.capGB)
    }

    func testSaveOverwritesPreviousState() {
        let store = FileDataStore(url: url)
        store.save(AppState(plan: PlanConfig(capGB: 10, cycleResetDay: 1)))
        store.save(AppState(plan: PlanConfig(capGB: 99, cycleResetDay: 1)))
        XCTAssertEqual(store.load().plan.capGB, 99)
    }

    func testInMemoryStoreReturnsWhatWasSaved() {
        let store = InMemoryDataStore()
        let state = AppState(plan: PlanConfig(capGB: 7, cycleResetDay: 3))
        store.save(state)
        XCTAssertEqual(store.load(), state)
    }
}
