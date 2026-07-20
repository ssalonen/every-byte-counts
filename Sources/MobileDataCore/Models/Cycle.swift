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

    /// Signed correction (bytes) applied on top of the measured usage for this
    /// cycle. Set by calibrating against the carrier's own figure — the on-device
    /// counters only see traffic from install onward, so a mid-cycle install
    /// under-counts until corrected. `nil` means never calibrated. The correction
    /// is folded into `totalCellular` at close and does not carry into the next
    /// cycle (the carrier's counter resets too). Optional so state persisted
    /// before this field existed still decodes.
    public var manualAdjustmentCellular: Int64?

    public init(
        id: UUID = UUID(),
        start: Date,
        end: Date,
        baselineCumulativeCellular: DataSize,
        baselineCumulativeWifi: DataSize,
        totalCellular: DataSize? = nil,
        capGBAtClose: Double? = nil,
        manualAdjustmentCellular: Int64? = nil
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.baselineCumulativeCellular = baselineCumulativeCellular
        self.baselineCumulativeWifi = baselineCumulativeWifi
        self.totalCellular = totalCellular
        self.capGBAtClose = capGBAtClose
        self.manualAdjustmentCellular = manualAdjustmentCellular
    }

    public var isClosed: Bool { totalCellular != nil }

    /// The counter-measured usage with this cycle's manual calibration applied,
    /// clamped at zero (a downward calibration can never go negative).
    public func calibratedUsage(measured: DataSize) -> DataSize {
        let adjusted = Int64(clamping: measured.bytes) + (manualAdjustmentCellular ?? 0)
        return adjusted > 0 ? DataSize(bytes: UInt64(adjusted)) : .zero
    }

    public func contains(_ date: Date) -> Bool {
        date >= start && date < end
    }
}
