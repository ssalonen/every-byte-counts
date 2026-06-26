import Foundation

/// Where the current cycle is heading.
public enum ForecastStatus: String, Equatable, Sendable {
    case safe
    case atRisk
    case over
}

/// The forecasting output (design §2). The headline is `remainingDailyBudget`;
/// the projection and status give the supporting "on pace to…" picture, and
/// `overageCost` carries the euro estimate when projected to exceed.
public struct Forecast: Equatable, Sendable {
    /// "You can use X GB/day for the remaining N days and stay under the cap."
    public var remainingDailyBudgetGB: Double
    /// Projected total cellular usage at cycle end.
    public var projectedTotalGB: Double
    /// Projected gigabytes over the cap (0 if under).
    public var projectedExcessGB: Double
    public var status: ForecastStatus
    /// Recency-weighted average daily usage that drove the projection.
    public var weightedDailyAverageGB: Double
    /// Euro cost of the projected overage, via the active cost strategy.
    public var overageCostEUR: Double
    public var overageBasis: String

    public init(
        remainingDailyBudgetGB: Double,
        projectedTotalGB: Double,
        projectedExcessGB: Double,
        status: ForecastStatus,
        weightedDailyAverageGB: Double,
        overageCostEUR: Double,
        overageBasis: String
    ) {
        self.remainingDailyBudgetGB = remainingDailyBudgetGB
        self.projectedTotalGB = projectedTotalGB
        self.projectedExcessGB = projectedExcessGB
        self.status = status
        self.weightedDailyAverageGB = weightedDailyAverageGB
        self.overageCostEUR = overageCostEUR
        self.overageBasis = overageBasis
    }
}
