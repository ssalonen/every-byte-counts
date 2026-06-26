import Foundation

/// A byte quantity with convenience conversions.
///
/// Carriers quote quotas in *decimal* gigabytes (1 GB = 1,000,000,000 bytes), so
/// that is the convention used throughout the app for anything user-facing. The
/// raw interface counters are also plain byte counts, so everything lines up.
public struct DataSize: Equatable, Comparable, Hashable, Codable, Sendable {
    /// Bytes per decimal gigabyte, matching how operators bill quotas.
    public static let bytesPerGB: Double = 1_000_000_000

    public var bytes: UInt64

    public init(bytes: UInt64) {
        self.bytes = bytes
    }

    public init(gigabytes: Double) {
        // Guard against negative inputs producing a wildly large UInt64.
        let clamped = max(0, gigabytes)
        self.bytes = UInt64((clamped * DataSize.bytesPerGB).rounded())
    }

    public var gigabytes: Double {
        Double(bytes) / DataSize.bytesPerGB
    }

    public var megabytes: Double {
        Double(bytes) / 1_000_000
    }

    public static let zero = DataSize(bytes: 0)

    public static func < (lhs: DataSize, rhs: DataSize) -> Bool {
        lhs.bytes < rhs.bytes
    }

    /// Saturating subtraction — never underflows the unsigned counter.
    public func subtractingSaturating(_ other: DataSize) -> DataSize {
        bytes >= other.bytes ? DataSize(bytes: bytes - other.bytes) : .zero
    }

    public static func + (lhs: DataSize, rhs: DataSize) -> DataSize {
        DataSize(bytes: lhs.bytes + rhs.bytes)
    }
}
