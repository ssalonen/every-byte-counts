import Foundation
@testable import MobileDataCore

/// A scriptable counter reader for tests. Set `cellular`/`wifi` (raw since-boot
/// bytes), call into the engine, then mutate them to simulate traffic or a
/// reboot (set them lower).
final class MockCounterReader: CounterReader {
    var cellular: UInt64
    var wifi: UInt64
    var shouldThrow = false

    init(cellular: UInt64 = 0, wifi: UInt64 = 0) {
        self.cellular = cellular
        self.wifi = wifi
    }

    func read() throws -> CounterReading {
        if shouldThrow { throw CounterReaderError.interfaceEnumerationFailed }
        return CounterReading(cellular: DataSize(bytes: cellular), wifi: DataSize(bytes: wifi))
    }

    /// Add raw traffic to both interfaces.
    func add(cellular dc: UInt64, wifi dw: UInt64 = 0) {
        cellular += dc
        wifi += dw
    }

    /// Simulate a reboot: counters reset to zero.
    func reboot() {
        cellular = 0
        wifi = 0
    }
}

enum TestDates {
    static let utc = TimeZone(identifier: "UTC")!

    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = utc
        return c
    }

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day
        comps.hour = hour; comps.minute = minute
        comps.timeZone = utc
        return calendar.date(from: comps)!
    }
}

let GB: UInt64 = 1_000_000_000
