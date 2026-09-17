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

/// A reader that reports per-interface, per-direction counters the way a device
/// does, so tests can script the three events that make a counter fall — a
/// 32-bit wrap, an interface being re-created, and a reboot — independently of
/// one another. Byte counters wrap at 2³² exactly as the kernel's do.
final class InterfaceMockReader: CounterReader {
    private(set) var cellular: InterfaceCounters
    private(set) var wifi: InterfaceCounters
    var bootTime: Date
    var shouldThrow = false
    /// Next interface index handed out when an interface is re-created.
    private var nextGeneration: UInt32 = 3

    static let counterWidth: UInt64 = 1 << 32
    /// Rough bytes-per-packet, so scripted traffic moves the packet counters too.
    static let bytesPerPacket: UInt64 = 1_500

    init(
        cellularIn: UInt64 = 0,
        cellularOut: UInt64 = 0,
        wifiIn: UInt64 = 0,
        wifiOut: UInt64 = 0,
        bootTime: Date = TestDates.date(2025, 1, 1, 0)
    ) {
        self.cellular = InterfaceCounters(
            name: "pdp_ip0", kind: .cellular, generation: 1,
            inBytes: cellularIn, outBytes: cellularOut,
            inPackets: cellularIn / Self.bytesPerPacket, outPackets: cellularOut / Self.bytesPerPacket
        )
        self.wifi = InterfaceCounters(
            name: "en0", kind: .wifi, generation: 2,
            inBytes: wifiIn, outBytes: wifiOut,
            inPackets: wifiIn / Self.bytesPerPacket, outPackets: wifiOut / Self.bytesPerPacket
        )
        self.bootTime = bootTime
    }

    func read() throws -> CounterReading {
        if shouldThrow { throw CounterReaderError.interfaceEnumerationFailed }
        return CounterReading(interfaces: [cellular, wifi], bootTime: bootTime)
    }

    /// Push traffic through an interface, wrapping its 32-bit counters like the
    /// kernel does.
    func addCellular(in inBytes: UInt64, out outBytes: UInt64 = 0) {
        cellular = Self.advancing(cellular, in: inBytes, out: outBytes)
    }

    func addWifi(in inBytes: UInt64, out outBytes: UInt64 = 0) {
        wifi = Self.advancing(wifi, in: inBytes, out: outBytes)
    }

    /// Simulate iOS tearing down and re-creating the cellular interface (airplane
    /// mode, SIM switch): counters zeroed, fresh interface index, same boot.
    func restartCellularInterface() {
        nextGeneration += 1
        cellular = InterfaceCounters(
            name: cellular.name, kind: .cellular, generation: nextGeneration,
            inBytes: 0, outBytes: 0, inPackets: 0, outPackets: 0
        )
    }

    /// Simulate a reboot: new boot time, every counter back to zero.
    func reboot(at date: Date? = nil) {
        bootTime = date ?? bootTime.addingTimeInterval(86_400)
        nextGeneration += 1
        cellular = InterfaceCounters(
            name: cellular.name, kind: .cellular, generation: 1,
            inBytes: 0, outBytes: 0, inPackets: 0, outPackets: 0
        )
        wifi = InterfaceCounters(
            name: wifi.name, kind: .wifi, generation: 2,
            inBytes: 0, outBytes: 0, inPackets: 0, outPackets: 0
        )
    }

    private static func advancing(
        _ counters: InterfaceCounters, in inBytes: UInt64, out outBytes: UInt64
    ) -> InterfaceCounters {
        var advanced = counters
        advanced.inBytes = (counters.inBytes &+ inBytes) % counterWidth
        advanced.outBytes = (counters.outBytes &+ outBytes) % counterWidth
        advanced.inPackets = counters.inPackets &+ inBytes / bytesPerPacket
        advanced.outPackets = counters.outPackets &+ outBytes / bytesPerPacket
        return advanced
    }
}
