import Foundation

/// A raw read of the system-wide interface byte counters at a moment in time.
/// Both figures are cumulative-since-boot and reset to zero on reboot.
public struct CounterReading: Equatable, Sendable {
    public var cellular: DataSize
    public var wifi: DataSize

    public init(cellular: DataSize, wifi: DataSize) {
        self.cellular = cellular
        self.wifi = wifi
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
