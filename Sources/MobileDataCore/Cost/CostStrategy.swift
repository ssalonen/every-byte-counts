import Foundation

/// The result of a cost estimate: a euro figure plus a human-readable basis the
/// UI can show verbatim (design §5).
public struct CostEstimate: Equatable, Sendable {
    public var amountEUR: Double
    /// e.g. "3.4 GB over × €5.00/GB".
    public var basis: String

    public init(amountEUR: Double, basis: String) {
        self.amountEUR = amountEUR
        self.basis = basis
    }

    public static let none = CostEstimate(amountEUR: 0, basis: "No overage")
}

/// A swappable cost model (design §5). The UI binds to this protocol, never to a
/// concrete calculation, so stepped/throttle/roaming variants slot in later
/// without reworking call sites.
public protocol CostStrategy {
    /// Estimates the cost of `excessGB` gigabytes over the cap. `excessGB` is the
    /// projected or actual overage and is assumed already clamped to ≥ 0.
    func estimate(excessGB: Double) -> CostEstimate
}

/// Builds the active strategy from the persisted, parameterised config (design
/// §6: cost stored as type + params). Centralising the mapping here means adding
/// a model is one new `case` plus one new strategy.
public enum CostStrategyFactory {
    public static func strategy(for config: CostModelConfig) -> CostStrategy {
        switch config {
        case let .flatRate(eurPerGB):
            return FlatRateCostStrategy(eurPerGB: eurPerGB)
        case let .stepped(blockGB, eurPerBlock):
            return SteppedCostStrategy(blockGB: blockGB, eurPerBlock: eurPerBlock)
        case .throttle:
            return ThrottleCostStrategy()
        }
    }
}
