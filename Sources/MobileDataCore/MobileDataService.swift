import Foundation

/// The single entry point the app and widget call into (design §4: neither
/// surface owns business logic). Wraps the `SamplingEngine` and the read-side
/// calculators so a caller can `sample()` and then `report()` without knowing how
/// any of it is wired.
public final class MobileDataService {
    private let store: DataStore
    private let engine: SamplingEngine
    private let usageCalculator: UsageCalculator
    private let aggregator: DailyAggregator
    private let forecaster: Forecaster

    public init(
        store: DataStore,
        reader: CounterReader,
        calendar: BillingCycleCalendar = BillingCycleCalendar(),
        aggregator: DailyAggregator = DailyAggregator(),
        forecaster: Forecaster = Forecaster()
    ) {
        self.store = store
        self.aggregator = aggregator
        self.forecaster = forecaster
        self.usageCalculator = UsageCalculator(calendar: calendar)
        self.engine = SamplingEngine(
            store: store,
            reader: reader,
            calendar: calendar,
            aggregator: aggregator
        )
    }

    /// Convenience factory for the real app: a file store in the App Group plus
    /// the live interface counter reader.
    #if canImport(Darwin)
    public static func live(appGroupIdentifier: String, fileName: String = "mobiledata.json") -> MobileDataService? {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else { return nil }
        let store = FileDataStore(url: container.appendingPathComponent(fileName))
        return MobileDataService(store: store, reader: InterfaceCounterReader())
    }
    #endif

    // MARK: - Sampling

    /// Take a sample (design §4). Call from app launch/foreground and from each
    /// widget timeline refresh.
    @discardableResult
    public func sample(now: Date = Date()) -> SampleResult? {
        engine.sample(now: now)
    }

    // MARK: - Reads

    public func currentState() -> AppState { store.load() }

    /// The composed dashboard/widget report for the current cycle.
    public func report(asOf now: Date = Date()) -> UsageReport {
        let state = store.load()
        let summary = usageCalculator.summary(for: state, asOf: now)

        let cycleRange = (summary.cycleStart, summary.cycleEnd)
        let daily = aggregator.dailyTotals(from: state.snapshots, in: cycleRange)

        let strategy = CostStrategyFactory.strategy(for: state.plan.costModel)
        let forecast = forecaster.forecast(
            dailyTotals: daily,
            used: summary.used,
            capGB: state.plan.capGB,
            daysRemaining: summary.daysRemaining,
            costStrategy: strategy
        )
        let today = aggregator.calendar.startOfDay(for: now)
        let usedToday = daily.first { $0.date == today }?.cellular ?? .zero
        return UsageReport(summary: summary, forecast: forecast, dailyTotals: daily, usedToday: usedToday, plan: state.plan)
    }

    /// Closed cycles as history rows, newest first (design §2).
    public func cycleHistory() -> [CycleSummary] {
        let state = store.load()
        return state.closedCycles.reversed().map { cycle in
            let total = cycle.totalCellular ?? .zero
            let cap = cycle.capGBAtClose ?? state.plan.capGB
            let overage = max(0, total.gigabytes - cap)
            let strategy = CostStrategyFactory.strategy(for: state.plan.costModel)
            let cost = strategy.estimate(excessGB: overage)
            return CycleSummary(
                id: cycle.id,
                start: cycle.start,
                end: cycle.end,
                total: total,
                capGB: cap,
                overageGB: overage,
                estimatedCostEUR: cost.amountEUR
            )
        }
    }

    // MARK: - Calibration

    /// Aligns the current cycle's usage with the carrier's own figure — the
    /// on-device counters only see traffic from install onward, so installing
    /// mid-cycle under-counts until the user calibrates. Stores the difference
    /// as a signed per-cycle correction: future samples keep counting on top of
    /// it, alerts and forecasts use the corrected figure, and the correction is
    /// folded into the cycle's total at close without carrying into the next
    /// cycle. Returns `false` if no billing cycle could be established (counter
    /// unreadable on a fresh install).
    @discardableResult
    public func calibrate(usedThisCycle target: DataSize, now: Date = Date()) -> Bool {
        engine.sample(now: now) // ensure a cycle is open and the counters are fresh
        var state = store.load()
        guard var cycle = state.currentCycle, cycle.contains(now) else { return false }
        let measured = state.latestSnapshot?.cumulativeCellular
            .subtractingSaturating(cycle.baselineCumulativeCellular) ?? .zero
        cycle.manualAdjustmentCellular = Int64(clamping: target.bytes) - Int64(clamping: measured.bytes)
        state.currentCycle = cycle
        store.save(state)
        return true
    }

    // MARK: - Settings

    public func updatePlan(_ transform: (inout PlanConfig) -> Void) {
        var state = store.load()
        transform(&state.plan)
        store.save(state)
    }
}
