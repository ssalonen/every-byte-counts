import XCTest
@testable import MobileDataCore

final class SamplingEngineTests: XCTestCase {
    private func makeEngine(_ reader: MockCounterReader, store: InMemoryDataStore) -> SamplingEngine {
        SamplingEngine(
            store: store,
            reader: reader,
            calendar: BillingCycleCalendar(calendar: TestDates.calendar)
        )
    }

    func testFirstSampleStartsCumulativeAtZero() {
        let store = InMemoryDataStore(AppState(plan: PlanConfig(capGB: 20, cycleResetDay: 1)))
        let reader = MockCounterReader(cellular: 3 * GB) // pre-install traffic this boot
        let engine = makeEngine(reader, store: store)

        let result = engine.sample(now: TestDates.date(2026, 3, 1, 10))
        XCTAssertEqual(result?.snapshot.cumulativeCellular, .zero)
        XCTAssertNotNil(store.load().installDate)
        XCTAssertNotNil(store.load().currentCycle)
    }

    func testSecondSampleAccumulatesDelta() {
        let store = InMemoryDataStore(AppState(plan: PlanConfig(capGB: 20, cycleResetDay: 1)))
        let reader = MockCounterReader(cellular: 1 * GB)
        let engine = makeEngine(reader, store: store)

        engine.sample(now: TestDates.date(2026, 3, 1, 10))
        reader.add(cellular: 2 * GB) // 2 GB of traffic
        let result = engine.sample(now: TestDates.date(2026, 3, 1, 12))

        XCTAssertEqual(result?.snapshot.cumulativeCellular.bytes, 2 * GB)
        XCTAssertFalse(result?.didReboot ?? true)
    }

    func testRebootIsDetectedAndCounted() {
        let store = InMemoryDataStore(AppState(plan: PlanConfig(capGB: 20, cycleResetDay: 1)))
        let reader = MockCounterReader(cellular: 1 * GB)
        let engine = makeEngine(reader, store: store)

        engine.sample(now: TestDates.date(2026, 3, 1, 10))     // cumulative 0
        reader.add(cellular: 3 * GB)                            // raw 4 GB
        engine.sample(now: TestDates.date(2026, 3, 1, 12))     // cumulative 3 GB
        reader.reboot()                                        // counters → 0
        reader.add(cellular: 500_000_000)                      // 0.5 GB after reboot
        let result = engine.sample(now: TestDates.date(2026, 3, 1, 14))

        XCTAssertTrue(result?.didReboot ?? false)
        // 3 GB before + 0.5 GB after reboot = 3.5 GB cumulative.
        XCTAssertEqual(result?.snapshot.cumulativeCellular.bytes, 3 * GB + 500_000_000)
    }

    func testCycleRolloverClosesAndRebases() {
        let store = InMemoryDataStore(AppState(plan: PlanConfig(capGB: 20, cycleResetDay: 1)))
        let reader = MockCounterReader(cellular: 0)
        let engine = makeEngine(reader, store: store)

        engine.sample(now: TestDates.date(2026, 3, 5, 10))   // open March cycle
        reader.add(cellular: 8 * GB)
        engine.sample(now: TestDates.date(2026, 3, 20, 10))  // 8 GB used in March
        reader.add(cellular: 2 * GB)
        let result = engine.sample(now: TestDates.date(2026, 4, 2, 10)) // now in April

        XCTAssertTrue(result?.didRolloverCycle ?? false)
        let state = store.load()
        XCTAssertEqual(state.closedCycles.count, 1)
        // March closed total = 10 GB cumulative - 0 baseline.
        XCTAssertEqual(state.closedCycles.first?.totalCellular?.bytes, 10 * GB)
        XCTAssertEqual(state.closedCycles.first?.capGBAtClose, 20)
        // New April cycle rebased at 10 GB → usage so far 0.
        XCTAssertEqual(state.currentCycle?.baselineCumulativeCellular.bytes, 10 * GB)
    }

    func testGapSpanningMultipleCyclesClosesOnlyTheOpenOne() {
        // Documented limitation: if the app/widget never samples for >1 cycle,
        // intermediate cycles have no data and are not reconstructed. The open
        // cycle closes and a new one opens for "now"; skipped months are absent.
        let store = InMemoryDataStore(AppState(plan: PlanConfig(capGB: 20, cycleResetDay: 1)))
        let reader = MockCounterReader(cellular: 0)
        let engine = makeEngine(reader, store: store)

        engine.sample(now: TestDates.date(2026, 3, 5, 10))   // open March cycle
        reader.add(cellular: 6 * GB)
        engine.sample(now: TestDates.date(2026, 5, 20, 10))  // jump to May (skips April)

        let state = store.load()
        XCTAssertEqual(state.closedCycles.count, 1, "only the previously-open cycle closes")
        XCTAssertEqual(state.closedCycles.first?.start, TestDates.date(2026, 3, 1, 0, 0))
        XCTAssertEqual(state.currentCycle?.start, TestDates.date(2026, 5, 1, 0, 0))
    }

    func testAlertsFireDuringSampling() {
        let store = InMemoryDataStore(AppState(plan: PlanConfig(capGB: 10, cycleResetDay: 1, alertThresholds: [0.5, 0.8])))
        let reader = MockCounterReader(cellular: 0)
        let engine = makeEngine(reader, store: store)

        engine.sample(now: TestDates.date(2026, 3, 1, 10))
        reader.add(cellular: 9 * GB) // 90% of 10 GB
        let result = engine.sample(now: TestDates.date(2026, 3, 2, 10))

        XCTAssertEqual(result?.pendingAlerts.map(\.threshold), [0.5, 0.8])
        // Re-sampling without more usage does not refire.
        let again = engine.sample(now: TestDates.date(2026, 3, 2, 11))
        XCTAssertTrue(again?.pendingAlerts.isEmpty ?? false)
    }

    func testWifiTrackedSeparatelyAndDoesNotAffectCellular() {
        let store = InMemoryDataStore(AppState(plan: PlanConfig(capGB: 20, cycleResetDay: 1)))
        let reader = MockCounterReader(cellular: 0, wifi: 0)
        let engine = makeEngine(reader, store: store)

        engine.sample(now: TestDates.date(2026, 3, 1, 10))
        reader.add(cellular: 1 * GB, wifi: 9 * GB)   // lots of WiFi, little cellular
        let result = engine.sample(now: TestDates.date(2026, 3, 1, 12))

        // WiFi is accumulated for context but the metered cellular figure ignores it.
        XCTAssertEqual(result?.snapshot.cumulativeCellular.bytes, 1 * GB)
        XCTAssertEqual(result?.snapshot.cumulativeWifi.bytes, 9 * GB)
    }

    func testRebootOnEitherInterfaceIsFlagged() {
        let store = InMemoryDataStore(AppState(plan: PlanConfig(capGB: 20, cycleResetDay: 1)))
        let reader = MockCounterReader(cellular: 2 * GB, wifi: 2 * GB)
        let engine = makeEngine(reader, store: store)

        engine.sample(now: TestDates.date(2026, 3, 1, 10))
        // Cellular keeps climbing, but WiFi counter drops (a reboot signature on
        // one interface). The pass must be flagged as a reboot.
        reader.cellular = 3 * GB
        reader.wifi = 100              // dropped below previous → reboot
        let result = engine.sample(now: TestDates.date(2026, 3, 1, 12))
        XCTAssertTrue(result?.didReboot ?? false)
        // First sample zeroed both cumulatives (no pre-sample backfill). Cellular
        // then climbs 2→3 GB (+1 GB); WiFi rebooted so only its post-reboot 100 B
        // counts. Cumulatives: cellular 1 GB, wifi 100 B.
        XCTAssertEqual(result?.snapshot.cumulativeCellular.bytes, 1 * GB)
        XCTAssertEqual(result?.snapshot.cumulativeWifi.bytes, 100)
    }

    func testFirstSampleHasNoAttributionTagByDefault() {
        let store = InMemoryDataStore(AppState(plan: PlanConfig(capGB: 20, cycleResetDay: 1)))
        let engine = makeEngine(MockCounterReader(cellular: GB), store: store)
        let result = engine.sample(now: TestDates.date(2026, 3, 1, 10))
        XCTAssertNil(result?.snapshot.attribution, "MVP leaves the roaming hook unset")
        XCTAssertTrue(result?.didRolloverCycle ?? false, "first sample opens the first cycle")
    }

    func testReadFailureLeavesStateUntouched() {
        let store = InMemoryDataStore(AppState(plan: PlanConfig(capGB: 20, cycleResetDay: 1)))
        let reader = MockCounterReader(cellular: 1 * GB)
        let engine = makeEngine(reader, store: store)
        engine.sample(now: TestDates.date(2026, 3, 1, 10))
        let before = store.load()

        reader.shouldThrow = true
        let result = engine.sample(now: TestDates.date(2026, 3, 1, 12))
        XCTAssertNil(result)
        XCTAssertEqual(store.load(), before)
    }

    func testSnapshotsArePruned() {
        let store = InMemoryDataStore(AppState(plan: PlanConfig(capGB: 20, cycleResetDay: 1)))
        let reader = MockCounterReader(cellular: 0)
        let engine = SamplingEngine(
            store: store,
            reader: reader,
            calendar: BillingCycleCalendar(calendar: TestDates.calendar),
            snapshotRetentionLimit: 5
        )
        for i in 0..<20 {
            reader.add(cellular: 1_000_000)
            engine.sample(now: TestDates.date(2026, 3, 1, 10).addingTimeInterval(Double(i) * 600))
        }
        XCTAssertEqual(store.load().snapshots.count, 5)
    }
}
