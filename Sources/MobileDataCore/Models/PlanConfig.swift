import Foundation

/// How an overage is priced. Stored as a *type + parameters* (design §5/§6) so
/// richer models can be added later without a data migration and without the UI
/// caring which one is active.
public enum CostModelConfig: Equatable, Codable, Sendable {
    /// MVP model: a flat euro rate applied to every excess gigabyte.
    case flatRate(eurPerGB: Double)

    /// Overage billed in fixed blocks (e.g. +1 GB for €X). Defined now so the
    /// persisted shape already accommodates it; no strategy is wired up for MVP.
    case stepped(blockGB: Double, eurPerBlock: Double)

    /// No charge — the connection is throttled past the cap. Cost is always €0.
    case throttle
}

/// User-configured plan: the quota, the billing cycle anchor and the cost model.
public struct PlanConfig: Equatable, Codable, Sendable {
    /// Monthly cap in decimal gigabytes.
    public var capGB: Double

    /// Day of the month (1–31) on which the billing cycle resets. Values past the
    /// end of a short month are clamped to that month's last day at evaluation.
    public var cycleResetDay: Int

    /// Pricing model used to estimate overage cost.
    public var costModel: CostModelConfig

    /// Thresholds (as fractions of the cap, e.g. 0.5/0.8/1.0) that trigger a
    /// local notification when first crossed in a cycle.
    public var alertThresholds: [Double]

    public init(
        capGB: Double,
        cycleResetDay: Int,
        costModel: CostModelConfig = .flatRate(eurPerGB: 5.0),
        alertThresholds: [Double] = [0.5, 0.8, 1.0]
    ) {
        self.capGB = capGB
        self.cycleResetDay = max(1, min(31, cycleResetDay))
        self.costModel = costModel
        self.alertThresholds = alertThresholds.sorted()
    }

    public var cap: DataSize { DataSize(gigabytes: capGB) }

    /// A reasonable starting configuration for first launch.
    public static let `default` = PlanConfig(capGB: 20, cycleResetDay: 1)
}
