import Foundation

/// A billing cycle. The current cycle is open-ended (no usable `total` until it
/// closes); past cycles are snapshotted with their final figures for the
/// month-by-month history (design §2/§6).
public struct Cycle: Equatable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var start: Date
    /// Exclusive end — the instant the next cycle begins.
    public var end: Date

    /// Cumulative cellular running total captured at `start`. Usage within the
    /// cycle is `currentCumulative - baselineCumulative`, which is how a reset is
    /// applied without ever zeroing the monotonic counter (design §2).
    public var baselineCumulativeCellular: DataSize
    public var baselineCumulativeWifi: DataSize

    /// Final cellular usage, set when the cycle closes. `nil` while open.
    public var totalCellular: DataSize?
    /// Cap that was in force for this cycle (caps can change between cycles).
    public var capGBAtClose: Double?

    public init(
        id: UUID = UUID(),
        start: Date,
        end: Date,
        baselineCumulativeCellular: DataSize,
        baselineCumulativeWifi: DataSize,
        totalCellular: DataSize? = nil,
        capGBAtClose: Double? = nil
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.baselineCumulativeCellular = baselineCumulativeCellular
        self.baselineCumulativeWifi = baselineCumulativeWifi
        self.totalCellular = totalCellular
        self.capGBAtClose = capGBAtClose
    }

    public var isClosed: Bool { totalCellular != nil }

    public func contains(_ date: Date) -> Bool {
        date >= start && date < end
    }
}
