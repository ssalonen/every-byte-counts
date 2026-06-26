import XCTest
@testable import MobileDataCore

final class CounterReaderTests: XCTestCase {

    func testCounterReadingHoldsValues() {
        let r = CounterReading(cellular: DataSize(bytes: 10), wifi: DataSize(bytes: 20))
        XCTAssertEqual(r.cellular.bytes, 10)
        XCTAssertEqual(r.wifi.bytes, 20)
    }

    #if canImport(Darwin)
    // Smoke test the real getifaddrs adapter on a Darwin host (CI macOS runner).
    // We can't assert specific byte counts, but reading must succeed and the
    // interface-name constants must be the ones iOS uses.
    func testInterfaceReaderReadsWithoutThrowing() throws {
        let reading = try InterfaceCounterReader().read()
        // Counters are unsigned and simply present; on a Mac the cellular
        // pdp_ip* interfaces are absent (→ 0) while en0 usually has traffic.
        XCTAssertGreaterThanOrEqual(reading.cellular.bytes, 0)
        XCTAssertGreaterThanOrEqual(reading.wifi.bytes, 0)
    }

    func testInterfaceIdentifiersAreCorrectForIOS() {
        XCTAssertEqual(InterfaceCounterReader.cellularPrefix, "pdp_ip")
        XCTAssertEqual(InterfaceCounterReader.wifiInterface, "en0")
    }
    #endif
}
