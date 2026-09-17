import XCTest
@testable import MobileDataCore

/// End-to-end sampling with the per-interface reader: what the dashboard would
/// have shown against what the carrier billed. A missed 32-bit wrap is exactly
/// the "app says GBs remaining, carrier says none" mismatch.
final class SamplingEngineWrapTests: XCTestCase {

    private let width = RebootAdjuster.counterWidth

    private func makeEngine(_ reader: InterfaceMockReader, store: InMemoryDataStore) -> SamplingEngine {
        SamplingEngine(
            store: store,
            reader: reader,
            calendar: BillingCycleCalendar(calendar: TestDates.calendar)
        )
    }

    private func usage(_ store: InMemoryDataStore) -> UInt64 {
        let state = store.load()
        guard let cycle = state.currentCycle, let latest = state.latestSnapshot else { return 0 }
        return latest.cumulativeCellular.subtractingSaturating(cycle.baselineCumulativeCellular).bytes
    }

    func testTrafficCrossingTheThirtyTwoBitWrapIsCountedInFull() {
        let store = InMemoryDataStore(AppState(plan: PlanConfig(capGB: 8, cycleResetDay: 1)))
        // Start the boot just short of the wrap point.
        let reader = InterfaceMockReader(cellularIn: width - 1_500_000_000, cellularOut: 200_000_000)
        let engine = makeEngine(reader, store: store)

        engine.sample(now: TestDates.date(2026, 3, 1, 8))

        // 5 GB down / 0.3 GB up over the cycle: the download counter rolls over
        // partway through, twice split across samples.
        reader.addCellular(in: 2 * GB, out: 100_000_000)
        engine.sample(now: TestDates.date(2026, 3, 3, 8))
        reader.addCellular(in: 3 * GB, out: 200_000_000)
        let result = engine.sample(now: TestDates.date(2026, 3, 6, 8))

        XCTAssertFalse(result?.didReboot ?? true, "a wrap is not a reboot")
        XCTAssertEqual(usage(store), 5 * GB + 300_000_000)
    }

    func testAWrapEntirelyInsideOneSampleIntervalIsStillCounted() {
        let store = InMemoryDataStore(AppState(plan: PlanConfig(capGB: 8, cycleResetDay: 1)))
        let reader = InterfaceMockReader(cellularIn: width - 500_000_000, cellularOut: 10_000_000)
        let engine = makeEngine(reader, store: store)

        engine.sample(now: TestDates.date(2026, 3, 1, 8))
        // The phone isn't opened for days; 3 GB passes and the counter wraps.
        reader.addCellular(in: 3 * GB, out: 50_000_000)
        engine.sample(now: TestDates.date(2026, 3, 5, 8))

        XCTAssertEqual(usage(store), 3 * GB + 50_000_000)
    }

    func testCellularInterfaceRestartDoesNotInventTraffic() {
        let store = InMemoryDataStore(AppState(plan: PlanConfig(capGB: 8, cycleResetDay: 1)))
        let reader = InterfaceMockReader(cellularIn: 1 * GB, cellularOut: 100_000_000)
        let engine = makeEngine(reader, store: store)

        engine.sample(now: TestDates.date(2026, 3, 1, 8))
        reader.addCellular(in: 400_000_000, out: 20_000_000)
        engine.sample(now: TestDates.date(2026, 3, 2, 8))

        // Airplane mode toggled: pdp_ip0 is re-created with zeroed counters.
        reader.restartCellularInterface()
        reader.addCellular(in: 300_000_000, out: 10_000_000)
        let result = engine.sample(now: TestDates.date(2026, 3, 3, 8))

        XCTAssertFalse(result?.didReboot ?? true, "one interface restarting is not a reboot")
        XCTAssertEqual(usage(store), 420_000_000 + 310_000_000)
    }

    func testRebootIsDetectedFromTheBootClock() {
        let store = InMemoryDataStore(AppState(plan: PlanConfig(capGB: 8, cycleResetDay: 1)))
        let reader = InterfaceMockReader(cellularIn: 1 * GB, cellularOut: 50_000_000)
        let engine = makeEngine(reader, store: store)

        engine.sample(now: TestDates.date(2026, 3, 1, 8))
        reader.addCellular(in: 2 * GB, out: 100_000_000)
        engine.sample(now: TestDates.date(2026, 3, 2, 8))

        reader.reboot()
        reader.addCellular(in: 600_000_000, out: 30_000_000)
        let result = engine.sample(now: TestDates.date(2026, 3, 3, 8))

        XCTAssertTrue(result?.didReboot ?? false)
        XCTAssertEqual(usage(store), 2_100_000_000 + 630_000_000)
    }

    func testPerInterfaceCountersArePersistedWithTheSnapshot() {
        let store = InMemoryDataStore(AppState(plan: PlanConfig(capGB: 8, cycleResetDay: 1)))
        let reader = InterfaceMockReader(cellularIn: 1 * GB, cellularOut: 10_000_000, wifiIn: 5 * GB)
        let engine = makeEngine(reader, store: store)

        let result = engine.sample(now: TestDates.date(2026, 3, 1, 8))

        XCTAssertEqual(result?.snapshot.interfaces?.count, 2)
        XCTAssertEqual(result?.snapshot.bootTime, reader.bootTime)
        XCTAssertEqual(result?.snapshot.rawCellular.bytes, 1 * GB + 10_000_000)
    }

    func testUpgradeFromASnapshotWithoutPerInterfaceCountersKeepsCounting() {
        // State written by a build that stored only the summed totals: the next
        // sample has to fall back to diffing those, then carry on precisely.
        let legacy = Snapshot(
            timestamp: TestDates.date(2026, 3, 1, 8),
            rawCellular: DataSize(bytes: 1 * GB),
            rawWifi: .zero,
            cumulativeCellular: DataSize(bytes: 2 * GB),
            cumulativeWifi: .zero
        )
        let state = AppState(
            plan: PlanConfig(capGB: 8, cycleResetDay: 1),
            snapshots: [legacy],
            currentCycle: Cycle(
                start: TestDates.date(2026, 3, 1, 0),
                end: TestDates.date(2026, 4, 1, 0),
                baselineCumulativeCellular: .zero,
                baselineCumulativeWifi: .zero
            )
        )
        let store = InMemoryDataStore(state)
        let reader = InterfaceMockReader(cellularIn: 1 * GB, cellularOut: 500_000_000)
        let engine = makeEngine(reader, store: store)

        engine.sample(now: TestDates.date(2026, 3, 2, 8))   // summed 1.5 GB vs 1 GB → +0.5 GB
        reader.addCellular(in: 250_000_000)
        engine.sample(now: TestDates.date(2026, 3, 3, 8))   // per-interface from here

        XCTAssertEqual(usage(store), 2 * GB + 500_000_000 + 250_000_000)
    }
}
