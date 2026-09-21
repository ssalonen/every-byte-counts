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

    // The per-interface break-out is what lets the engine tell a 32-bit wrap
    // from a restarted counter, so the adapter has to actually populate it.
    func testInterfaceReaderReportsPerInterfaceCountersAndABootClock() throws {
        let reading = try InterfaceCounterReader().read()

        XCTAssertNotNil(reading.bootTime, "kern.boottime is always readable on Darwin")
        for interface in reading.interfaces {
            XCTAssertNotEqual(interface.generation, 0, "\(interface.name) needs an interface index")
            XCTAssertEqual(interface.totalBytes, interface.inBytes + interface.outBytes)
        }
        // The headline totals must agree with the per-interface break-out.
        let cellular = reading.interfaces.filter { $0.kind == .cellular }.reduce(UInt64(0)) { $0 + $1.totalBytes }
        let wifi = reading.interfaces.filter { $0.kind == .wifi }.reduce(UInt64(0)) { $0 + $1.totalBytes }
        XCTAssertEqual(reading.cellular.bytes, cellular)
        XCTAssertEqual(reading.wifi.bytes, wifi)
    }

    func testInterfaceIdentifiersAreCorrectForIOS() {
        XCTAssertEqual(InterfaceCounterReader.cellularPrefix, "pdp_ip")
        XCTAssertEqual(InterfaceCounterReader.wifiInterface, "en0")
    }
    #endif
}
