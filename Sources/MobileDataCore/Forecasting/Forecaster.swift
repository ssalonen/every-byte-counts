import Foundation

/// Recency-weighted forecasting engine (design §2).
///
/// Projection model:
///   * Take the per-day usage so far this cycle.
///   * Weight days by recency with an exponential decay (most recent day weight
///     1, the day before `decay`, etc.), so a recent change in habits dominates
///     the early-cycle days.
///   * `projectedTotal = used + weightedDailyAverage × daysRemaining`.
///   * `remainingDailyBudget = (cap − used) / daysRemaining`, the headline.
///
/// Weekday/weekend awareness is intentionally left out (design says nice-to-have).
public struct Forecaster {
    /// Exponential decay applied per day into the past (0 < decay ≤ 1). Lower =
    /// more aggressively recency-weighted. 0.8 keeps ~5 days materially relevant.
    public let decay: Double

    /// Fraction of the cap at which "safe" becomes "at risk" even when not yet
    /// projected over (gives an amber band below 100%).
    public let atRiskFraction: Double

    public init(decay: Double = 0.8, atRiskFraction: Double = 0.85) {
        self.decay = max(0.01, min(1.0, decay))
        self.atRiskFraction = atRiskFraction
    }

    /// - Parameters:
    ///   - dailyTotals: per-day usage for the current cycle (any order).
    ///   - used: usage so far this cycle.
    ///   - capGB: the quota.
    ///   - daysRemaining: whole days left, including today (≥ 1).
    ///   - costStrategy: active cost model for the overage euro figure.
    public func forecast(
        dailyTotals: [DailyTotal],
        used: DataSize,
        capGB: Double,
        daysRemaining: Int,
        costStrategy: CostStrategy
    ) -> Forecast {
        let usedGB = used.gigabytes
        let remainingDays = max(1, daysRemaining)
        let remainingBudget = max(0, (capGB - usedGB) / Double(remainingDays))

        let weightedAvg = weightedDailyAverageGB(dailyTotals)
        let projectedTotal = usedGB + weightedAvg * Double(remainingDays)
        let projectedExcess = max(0, projectedTotal - capGB)

        let status: ForecastStatus
        if projectedExcess > 0 {
            status = .over
        } else if projectedTotal >= capGB * atRiskFraction {
            status = .atRisk
        } else {
            status = .safe
        }

        let cost = costStrategy.estimate(excessGB: projectedExcess)

        return Forecast(
            remainingDailyBudgetGB: remainingBudget,
            projectedTotalGB: projectedTotal,
            projectedExcessGB: projectedExcess,
            status: status,
            weightedDailyAverageGB: weightedAvg,
            overageCostEUR: cost.amountEUR,
            overageBasis: cost.basis
        )
    }

    /// Exponentially recency-weighted mean of daily usage in GB.
    func weightedDailyAverageGB(_ dailyTotals: [DailyTotal]) -> Double {
        guard !dailyTotals.isEmpty else { return 0 }
        let ordered = dailyTotals.sorted { $0.date < $1.date }
        let lastIndex = ordered.count - 1

        var weightedSum = 0.0
        var weightTotal = 0.0
        for (i, day) in ordered.enumerated() {
            let daysAgo = lastIndex - i
            let weight = pow(decay, Double(daysAgo))
            weightedSum += day.cellular.gigabytes * weight
            weightTotal += weight
        }
        return weightTotal == 0 ? 0 : weightedSum / weightTotal
    }
}
