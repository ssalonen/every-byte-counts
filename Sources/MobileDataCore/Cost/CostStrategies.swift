import Foundation

/// MVP strategy (design §5): a flat €/GB applied to the excess only.
public struct FlatRateCostStrategy: CostStrategy {
    public let eurPerGB: Double

    public init(eurPerGB: Double) {
        self.eurPerGB = eurPerGB
    }

    public func estimate(excessGB: Double) -> CostEstimate {
        let excess = max(0, excessGB)
        guard excess > 0 else { return .none }
        let amount = excess * eurPerGB
        return CostEstimate(
            amountEUR: amount,
            basis: String(format: "%.2f GB over × €%.2f/GB", excess, eurPerGB)
        )
    }
}

/// Future variant (design §5): overage billed in whole fixed blocks. Wired up via
/// the factory so the abstraction is already exercised, even though the MVP UI
/// defaults to flat rate.
public struct SteppedCostStrategy: CostStrategy {
    public let blockGB: Double
    public let eurPerBlock: Double

    public init(blockGB: Double, eurPerBlock: Double) {
        self.blockGB = max(0.0001, blockGB)
        self.eurPerBlock = eurPerBlock
    }

    public func estimate(excessGB: Double) -> CostEstimate {
        let excess = max(0, excessGB)
        guard excess > 0 else { return .none }
        let blocks = Int((excess / blockGB).rounded(.up))
        let amount = Double(blocks) * eurPerBlock
        return CostEstimate(
            amountEUR: amount,
            basis: String(format: "%d × %.0f GB block @ €%.2f", blocks, blockGB, eurPerBlock)
        )
    }
}

/// Future variant (design §5): no charge, speed reduced past the cap.
public struct ThrottleCostStrategy: CostStrategy {
    public init() {}

    public func estimate(excessGB: Double) -> CostEstimate {
        CostEstimate(amountEUR: 0, basis: "Throttled past cap — no charge")
    }
}
