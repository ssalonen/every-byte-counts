import Foundation

/// Everything the dashboard and widget need in one value (design §4: both
/// surfaces read the same composed report from Core).
public struct UsageReport: Equatable, Sendable {
    public var summary: UsageSummary
    public var forecast: Forecast
    public var dailyTotals: [DailyTotal]
    public var plan: PlanConfig

    public init(summary: UsageSummary, forecast: Forecast, dailyTotals: [DailyTotal], plan: PlanConfig) {
        self.summary = summary
        self.forecast = forecast
        self.dailyTotals = dailyTotals
        self.plan = plan
    }
}

/// A closed cycle rendered for the month-by-month history view (design §2).
public struct CycleSummary: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var start: Date
    public var end: Date
    public var total: DataSize
    public var capGB: Double
    public var overageGB: Double
    public var estimatedCostEUR: Double

    public init(id: UUID, start: Date, end: Date, total: DataSize, capGB: Double, overageGB: Double, estimatedCostEUR: Double) {
        self.id = id
        self.start = start
        self.end = end
        self.total = total
        self.capGB = capGB
        self.overageGB = overageGB
        self.estimatedCostEUR = estimatedCostEUR
    }
}
