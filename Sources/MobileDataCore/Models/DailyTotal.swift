import Foundation

/// Cellular (and contextual WiFi) usage attributed to a single calendar day,
/// derived from the deltas between consecutive snapshots (design §6).
public struct DailyTotal: Equatable, Codable, Sendable, Identifiable {
    /// The day this total covers, normalised to the start of that day.
    public var date: Date
    public var cellular: DataSize
    public var wifi: DataSize

    public var id: Date { date }

    public init(date: Date, cellular: DataSize, wifi: DataSize = .zero) {
        self.date = date
        self.cellular = cellular
        self.wifi = wifi
    }
}
