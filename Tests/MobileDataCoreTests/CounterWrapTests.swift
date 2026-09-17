import XCTest
@testable import MobileDataCore

/// The three events that make a raw counter fall — a 32-bit wrap, an interface
/// being re-created, and a reboot — must be told apart: crediting a wrap as a
/// restart loses up to 4 GiB of real usage per wrap (the app reading lower than
/// the carrier), while crediting a restart as a wrap invents the same amount.
final class CounterWrapTests: XCTestCase {

    private let width = RebootAdjuster.counterWidth   // 2³²
    private let boot = TestDates.date(2025, 3, 1, 0)

    private func cellular(
        _ inBytes: UInt64, _ outBytes: UInt64,
        generation: UInt32 = 1, inPackets: UInt64 = 0, outPackets: UInt64 = 0
    ) -> InterfaceCounters {
        InterfaceCounters(
            name: "pdp_ip0", kind: .cellular, generation: generation,
            inBytes: inBytes, outBytes: outBytes,
            inPackets: inPackets, outPackets: outPackets
        )
    }

    // MARK: - Wraps

    func testWrappedCounterCreditsTheBytesBeforeTheWrap() {
        // 100 MB short of 2³², then 300 MB past it → 400 MB of traffic, no reboot.
        let previous = [cellular(width - 100_000_000, 0, inPackets: 1_000)]
        let current = [cellular(300_000_000, 0, inPackets: 1_300)]

        let result = RebootAdjuster.deltas(
            previous: previous, previousBootTime: boot,
            current: current, currentBootTime: boot
        )

        XCTAssertEqual(result.cellular.bytes, 400_000_000)
        XCTAssertFalse(result.didReboot)
    }

    func testWrapOnOneDirectionDoesNotDisturbTheOther() {
        let previous = [cellular(width - 1_000, 5_000, inPackets: 10, outPackets: 5)]
        let current = [cellular(2_000, 9_000, inPackets: 14, outPackets: 8)]

        let result = RebootAdjuster.deltas(
            previous: previous, previousBootTime: boot,
            current: current, currentBootTime: boot
        )

        XCTAssertEqual(result.cellular.bytes, 3_000 + 4_000)
        XCTAssertFalse(result.didReboot)
    }

    func testSummedTotalFallingWithNeitherCounterRestartingIsNotAReboot() {
        // in wrapped, out kept climbing: the *sum* fell, which the old pre-summed
        // diff read as a reboot and re-based on — dropping the whole cycle's
        // in-traffic. Per-interface diffing sees it for what it is.
        let previous = [cellular(width - 500_000_000, 2_000_000_000, inPackets: 900, outPackets: 900)]
        let current = [cellular(100_000_000, 2_100_000_000, inPackets: 1_000, outPackets: 1_000)]

        let result = RebootAdjuster.deltas(
            previous: previous, previousBootTime: boot,
            current: current, currentBootTime: boot
        )

        XCTAssertLessThan(current[0].totalBytes, previous[0].totalBytes, "the summed read did fall")
        XCTAssertEqual(result.cellular.bytes, 600_000_000 + 100_000_000)
        XCTAssertFalse(result.didReboot)
    }

    func testCounterAboveTheThirtyTwoBitRangeCannotWrap() {
        // A 64-bit counter never rolls at 2³², so a drop can only be a restart —
        // adding a wrap here would invent 4 GiB.
        let previous = [cellular(width + 1_000_000, 0)]
        let current = [cellular(2_000, 0)]

        let result = RebootAdjuster.deltas(
            previous: previous, previousBootTime: boot,
            current: current, currentBootTime: boot
        )

        XCTAssertEqual(result.cellular.bytes, 2_000)
    }

    // MARK: - Interface restarts (no reboot)

    func testReCreatedInterfaceCountsFromZeroRatherThanWrapping() {
        // Airplane-mode toggle: same name, fresh kernel index, counters zeroed.
        let previous = [cellular(3_000_000_000, 400_000_000, generation: 7, inPackets: 2_000, outPackets: 800)]
        let current = [cellular(12_000_000, 3_000_000, generation: 8, inPackets: 9, outPackets: 4)]

        let result = RebootAdjuster.deltas(
            previous: previous, previousBootTime: boot,
            current: current, currentBootTime: boot
        )

        XCTAssertEqual(result.cellular.bytes, 15_000_000)
        XCTAssertFalse(result.didReboot, "one interface restarting is not a reboot")
    }

    func testPacketCountersGoingBackwardsMarkARestartEvenWithTheSameIndex() {
        let previous = [cellular(3_000_000_000, 400_000_000, inPackets: 2_000, outPackets: 800)]
        let current = [cellular(12_000_000, 3_000_000, inPackets: 9, outPackets: 4)]

        let result = RebootAdjuster.deltas(
            previous: previous, previousBootTime: boot,
            current: current, currentBootTime: boot
        )

        XCTAssertEqual(result.cellular.bytes, 15_000_000)
    }

    func testCountersDroppingToNothingAtAllIsARestartNotAWrap() {
        // A re-created interface that has passed no traffic yet: bytes and packets
        // both back to zero. Only one *byte* direction fell (the other was already
        // zero), so the byte rule alone would credit a phantom wrap.
        let previous = [cellular(3_000_000_000, 0, inPackets: 2_000)]
        let current = [cellular(0, 0)]

        let result = RebootAdjuster.deltas(
            previous: previous, previousBootTime: boot,
            current: current, currentBootTime: boot
        )

        XCTAssertEqual(result.cellular.bytes, 0)
    }

    func testBothByteDirectionsFallingIsARestartWhenNoPacketCountsExist() {
        let previous = [cellular(3_000_000_000, 400_000_000)]
        let current = [cellular(12_000_000, 3_000_000)]

        let result = RebootAdjuster.deltas(
            previous: previous, previousBootTime: boot,
            current: current, currentBootTime: boot
        )

        XCTAssertEqual(result.cellular.bytes, 15_000_000)
    }

    func testInterfaceAppearingMidBootCountsEverythingItHasSeen() {
        let previous = [cellular(1_000, 500, inPackets: 2, outPackets: 1)]
        let current = [
            cellular(4_000, 1_500, inPackets: 5, outPackets: 3),
            InterfaceCounters(name: "pdp_ip1", kind: .cellular, generation: 9,
                              inBytes: 80_000, outBytes: 20_000, inPackets: 60, outPackets: 15)
        ]

        let result = RebootAdjuster.deltas(
            previous: previous, previousBootTime: boot,
            current: current, currentBootTime: boot
        )

        XCTAssertEqual(result.cellular.bytes, 3_000 + 1_000 + 100_000)
    }

    func testDisappearedInterfaceDoesNotSubtractFromTheTotal() {
        let previous = [
            cellular(1_000, 500, inPackets: 2, outPackets: 1),
            InterfaceCounters(name: "pdp_ip1", kind: .cellular, generation: 9,
                              inBytes: 80_000, outBytes: 20_000, inPackets: 60, outPackets: 15)
        ]
        let current = [cellular(4_000, 1_500, inPackets: 5, outPackets: 3)]

        let result = RebootAdjuster.deltas(
            previous: previous, previousBootTime: boot,
            current: current, currentBootTime: boot
        )

        XCTAssertEqual(result.cellular.bytes, 4_000)
    }

    // MARK: - Reboots

    func testBootTimeChangeIsARebootAndCountersAreCreditedFromZero() {
        let previous = [cellular(3_000_000_000, 100_000_000, inPackets: 2_000, outPackets: 900)]
        let current = [cellular(50_000_000, 5_000_000, inPackets: 40, outPackets: 10)]

        let result = RebootAdjuster.deltas(
            previous: previous, previousBootTime: boot,
            current: current, currentBootTime: boot.addingTimeInterval(7_200)
        )

        XCTAssertTrue(result.didReboot)
        XCTAssertEqual(result.cellular.bytes, 55_000_000)
    }

    func testClockJitterOnTheBootTimeIsNotAReboot() {
        let previous = [cellular(width - 10_000, 0, inPackets: 100)]
        let current = [cellular(5_000, 0, inPackets: 120)]

        let result = RebootAdjuster.deltas(
            previous: previous, previousBootTime: boot,
            current: current, currentBootTime: boot.addingTimeInterval(1.5)
        )

        XCTAssertFalse(result.didReboot, "boot time is disciplined by a second or so, not rebooted")
        XCTAssertEqual(result.cellular.bytes, 15_000, "still a wrap")
    }

    func testRebootIsInferredFromEveryInterfaceRestartingWhenNoBootClockExists() {
        let previous = [
            cellular(3_000_000_000, 100_000_000, inPackets: 2_000, outPackets: 900),
            InterfaceCounters(name: "en0", kind: .wifi, generation: 2,
                              inBytes: 900_000_000, outBytes: 40_000_000, inPackets: 700, outPackets: 300)
        ]
        let current = [
            cellular(20_000_000, 1_000_000, inPackets: 15, outPackets: 4),
            InterfaceCounters(name: "en0", kind: .wifi, generation: 2,
                              inBytes: 6_000_000, outBytes: 1_000_000, inPackets: 5, outPackets: 2)
        ]

        let result = RebootAdjuster.deltas(
            previous: previous, previousBootTime: nil,
            current: current, currentBootTime: nil
        )

        XCTAssertTrue(result.didReboot)
        XCTAssertEqual(result.cellular.bytes, 21_000_000)
        XCTAssertEqual(result.wifi.bytes, 7_000_000)
    }

    func testOneInterfaceRestartingWithNoBootClockIsNotAReboot() {
        let previous = [
            cellular(3_000_000_000, 100_000_000, inPackets: 2_000, outPackets: 900),
            InterfaceCounters(name: "en0", kind: .wifi, generation: 2,
                              inBytes: 900_000_000, outBytes: 40_000_000, inPackets: 700, outPackets: 300)
        ]
        let current = [
            cellular(20_000_000, 1_000_000, inPackets: 15, outPackets: 4),
            InterfaceCounters(name: "en0", kind: .wifi, generation: 2,
                              inBytes: 900_500_000, outBytes: 40_100_000, inPackets: 760, outPackets: 320)
        ]

        let result = RebootAdjuster.deltas(
            previous: previous, previousBootTime: nil,
            current: current, currentBootTime: nil
        )

        XCTAssertFalse(result.didReboot)
        XCTAssertEqual(result.cellular.bytes, 21_000_000)
        XCTAssertEqual(result.wifi.bytes, 600_000)
    }

    func testEmptyReadingsYieldNothing() {
        let result = RebootAdjuster.deltas(
            previous: [], previousBootTime: nil, current: [], currentBootTime: nil
        )

        XCTAssertEqual(result.cellular.bytes, 0)
        XCTAssertEqual(result.wifi.bytes, 0)
        XCTAssertFalse(result.didReboot)
    }

    // MARK: - Reading composition

    func testReadingFromInterfacesSumsEachKind() {
        let reading = CounterReading(
            interfaces: [
                cellular(1_000, 500),
                InterfaceCounters(name: "pdp_ip1", kind: .cellular, inBytes: 200, outBytes: 100),
                InterfaceCounters(name: "en0", kind: .wifi, inBytes: 7_000, outBytes: 3_000)
            ],
            bootTime: boot
        )

        XCTAssertEqual(reading.cellular.bytes, 1_800)
        XCTAssertEqual(reading.wifi.bytes, 10_000)
        XCTAssertEqual(reading.bootTime, boot)
        XCTAssertEqual(reading.interfaces.count, 3)
    }
}
