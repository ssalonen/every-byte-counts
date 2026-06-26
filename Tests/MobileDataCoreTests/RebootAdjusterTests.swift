import XCTest
@testable import MobileDataCore

final class RebootAdjusterTests: XCTestCase {
    func testNormalIncrement() {
        let r = RebootAdjuster.delta(previousRaw: DataSize(bytes: 100), currentRaw: DataSize(bytes: 350))
        XCTAssertEqual(r.delta.bytes, 250)
        XCTAssertFalse(r.didReboot)
    }

    func testRebootDetectedWhenCounterDrops() {
        // Previous 5 GB, now 200 MB → reboot; the new reading is the delta.
        let r = RebootAdjuster.delta(previousRaw: DataSize(bytes: 5 * GB), currentRaw: DataSize(bytes: 200_000_000))
        XCTAssertTrue(r.didReboot)
        XCTAssertEqual(r.delta.bytes, 200_000_000)
    }

    func testEqualCountersYieldZeroDelta() {
        let r = RebootAdjuster.delta(previousRaw: DataSize(bytes: 42), currentRaw: DataSize(bytes: 42))
        XCTAssertEqual(r.delta.bytes, 0)
        XCTAssertFalse(r.didReboot)
    }
}
