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
        try? FileManager.default.removeItem(at: url.appendingPathExtension("corrupt"))
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

    func testCorruptFileIsPreservedAsBackupAndSavingResumes() throws {
        let garbage = "this is not json".data(using: .utf8)!
        try garbage.write(to: url)
        let store = FileDataStore(url: url)

        XCTAssertEqual(store.load(), AppState())
        // The undecodable bytes must survive for recovery, not be overwritten.
        XCTAssertEqual(try Data(contentsOf: store.corruptBackupURL), garbage)

        // And the store behaves like a fresh install from here on.
        store.save(AppState(plan: PlanConfig(capGB: 33, cycleResetDay: 5)))
        XCTAssertEqual(store.load().plan.capGB, 33)
    }

    func testUnreadableFileBlocksSaveSoRealDataIsNotClobbered() throws {
        // A directory at the store's path is "exists but can't be read as data" —
        // the same shape as a data-protection failure before first unlock.
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let store = FileDataStore(url: url)

        XCTAssertEqual(store.load(), AppState(), "unreadable file degrades to defaults for display")
        store.save(AppState(plan: PlanConfig(capGB: 99, cycleResetDay: 1)))

        var isDirectory: ObjCBool = false
        _ = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        XCTAssertTrue(isDirectory.boolValue, "save after a failed read must not touch the store file")

        // Once the file becomes readable again (here: the blocker goes away and a
        // valid state exists), saving resumes.
        try FileManager.default.removeItem(at: url)
        FileDataStore(url: url).save(AppState(plan: PlanConfig(capGB: 12, cycleResetDay: 2)))
        XCTAssertEqual(store.load().plan.capGB, 12)
        store.save(AppState(plan: PlanConfig(capGB: 21, cycleResetDay: 3)))
        XCTAssertEqual(store.load().plan.capGB, 21)
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
