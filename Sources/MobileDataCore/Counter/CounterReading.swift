import Foundation

/// A raw read of the system-wide interface byte counters at a moment in time.
///
/// `cellular` / `wifi` are the summed totals the rest of the app displays;
/// `interfaces` keeps the same read broken out per interface and direction,
/// which is what the sampling engine diffs so a 32-bit counter wrap is told
/// apart from a counter restart. `bootTime` pins the reading to a boot, so a
/// reboot is recognised as such instead of being guessed at from a counter that
/// happened to fall.
public struct CounterReading: Equatable, Sendable {
    public var cellular: DataSize
    public var wifi: DataSize

    /// Per-interface, per-direction raw counters behind the two totals. Empty
    /// when the platform cannot report them, in which case the engine falls back
    /// to diffing the summed totals.
    public var interfaces: [InterfaceCounters]

    /// When the device last booted, if the platform can report it. Counters are
    /// cumulative since this instant and restart when it changes.
    public var bootTime: Date?

    public init(
        cellular: DataSize,
        wifi: DataSize,
        interfaces: [InterfaceCounters] = [],
        bootTime: Date? = nil
    ) {
        self.cellular = cellular
        self.wifi = wifi
        self.interfaces = interfaces
        self.bootTime = bootTime
    }

    /// Builds a reading from per-interface counters, summing each kind into the
    /// headline totals so the two views can never disagree.
    public init(interfaces: [InterfaceCounters], bootTime: Date? = nil) {
        var cellular: UInt64 = 0
        var wifi: UInt64 = 0
        for interface in interfaces {
            switch interface.kind {
            case .cellular: cellular &+= interface.totalBytes
            case .wifi: wifi &+= interface.totalBytes
            }
        }
        self.init(
            cellular: DataSize(bytes: cellular),
            wifi: DataSize(bytes: wifi),
            interfaces: interfaces,
            bootTime: bootTime
        )
    }
}

/// Reads the system interface counters. This is the single sanctioned data
/// source (design §1): an on-device, no-VPN, no-login read of the per-interface
/// byte totals. Abstracted behind a protocol so the sampling engine and its
/// tests don't depend on Darwin.
public protocol CounterReader {
    /// Returns the current cellular and WiFi byte totals, or throws if the
    /// counters could not be read.
    func read() throws -> CounterReading
}

public enum CounterReaderError: Error {
    case interfaceEnumerationFailed
}
