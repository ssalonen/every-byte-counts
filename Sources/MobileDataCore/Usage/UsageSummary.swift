import Foundation

/// The headline dashboard figures (design §2): used / remaining / % consumed /
/// days left, plus the data the widget needs for its glance.
public struct UsageSummary: Equatable, Sendable {
    public var used: DataSize
    public var cap: DataSize
    public var remaining: DataSize
    /// Fraction of the cap consumed (0…). Can exceed 1 when over the cap.
    public var fractionUsed: Double
    public var daysRemaining: Int
    public var daysElapsed: Int
    public var cycleStart: Date
    public var cycleEnd: Date

    public init(
        used: DataSize,
        cap: DataSize,
        remaining: DataSize,
        fractionUsed: Double,
        daysRemaining: Int,
        daysElapsed: Int,
        cycleStart: Date,
        cycleEnd: Date
    ) {
        self.used = used
        self.cap = cap
        self.remaining = remaining
        self.fractionUsed = fractionUsed
        self.daysRemaining = daysRemaining
        self.daysElapsed = daysElapsed
        self.cycleStart = cycleStart
        self.cycleEnd = cycleEnd
    }

    public var percentUsed: Double { fractionUsed * 100 }
    public var isOverCap: Bool { used > cap }
}
