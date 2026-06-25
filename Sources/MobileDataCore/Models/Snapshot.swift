import Foundation

/// One reading of the system interface counters, taken when the app is opened or
/// when the widget timeline refreshes (design §1/§4).
///
/// Two kinds of figure are stored side by side:
///   * `rawCellular` / `rawWifi` — the interface counter *as read*. These reset
///     to zero on every reboot, so they are only meaningful relative to the
///     previous reading from the same boot.
///   * `cumulativeCellular` / `cumulativeWifi` — a monotonic running total that
///     the sampling engine maintains across reboots. This is what every higher
///     level (daily totals, cycle usage, forecasting) is built on.
public struct Snapshot: Equatable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var timestamp: Date

    /// Raw cellular counter at `timestamp` (resets on reboot).
    public var rawCellular: DataSize
    /// Raw WiFi counter at `timestamp` (resets on reboot).
    public var rawWifi: DataSize

    /// Reboot-adjusted running total of cellular bytes since install.
    public var cumulativeCellular: DataSize
    /// Reboot-adjusted running total of WiFi bytes since install.
    public var cumulativeWifi: DataSize

    /// Extensibility hook (design §6): lets a future roaming meter classify the
    /// delta that *ended* at this snapshot (e.g. "home" vs "roaming") without a
    /// schema migration. Unused by the MVP.
    public var attribution: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        rawCellular: DataSize,
        rawWifi: DataSize,
        cumulativeCellular: DataSize,
        cumulativeWifi: DataSize,
        attribution: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.rawCellular = rawCellular
        self.rawWifi = rawWifi
        self.cumulativeCellular = cumulativeCellular
        self.cumulativeWifi = cumulativeWifi
        self.attribution = attribution
    }
}
