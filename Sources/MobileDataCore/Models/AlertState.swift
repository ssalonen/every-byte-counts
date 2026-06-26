import Foundation

/// Tracks which threshold alerts have already fired in the current cycle so a
/// notification is sent at most once per threshold per cycle (design §4/§6).
public struct AlertState: Equatable, Codable, Sendable {
    /// Identifies the cycle these fired-flags belong to. When the active cycle's
    /// id changes, the fired set is considered stale and reset.
    public var cycleID: UUID?

    /// Thresholds (as fractions of the cap) that have been notified this cycle.
    public var firedThresholds: Set<Double>

    public init(cycleID: UUID? = nil, firedThresholds: Set<Double> = []) {
        self.cycleID = cycleID
        self.firedThresholds = firedThresholds
    }

    public static let empty = AlertState()
}
