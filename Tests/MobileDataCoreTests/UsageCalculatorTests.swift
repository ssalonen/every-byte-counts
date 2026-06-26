import XCTest
@testable import MobileDataCore

final class UsageCalculatorTests: XCTestCase {
    let calc = UsageCalculator(calendar: BillingCycleCalendar(calendar: TestDates.calendar))

    func testNoCurrentCycleReportsZeroUsedAndCalendarBounds() {
        // Fresh install, no sample taken yet: used is zero, the full cap remains,
        // and the cycle window comes from the calendar (reset day 10).
        let state = AppState(plan: PlanConfig(capGB: 20, cycleResetDay: 10))
        let summary = calc.summary(for: state, asOf: TestDates.date(2026, 3, 15, 12))

        XCTAssertEqual(summary.used, .zero)
        XCTAssertEqual(summary.remaining.bytes, 20_000_000_000)
        XCTAssertEqual(summary.fractionUsed, 0)
        XCTAssertFalse(summary.isOverCap)
        XCTAssertEqual(summary.cycleStart, TestDates.date(2026, 3, 10, 0, 0))
        XCTAssertEqual(summary.cycleEnd, TestDates.date(2026, 4, 10, 0, 0))
    }

    func testUsageIsCumulativeMinusBaseline() {
        let now = TestDates.date(2026, 3, 15, 12)
        let cycle = Cycle(
            start: TestDates.date(2026, 3, 1), end: TestDates.date(2026, 4, 1),
            baselineCumulativeCellular: DataSize(gigabytes: 4), baselineCumulativeWifi: .zero
        )
        let snap = Snapshot(
            timestamp: now,
            rawCellular: .zero, rawWifi: .zero,
            cumulativeCellular: DataSize(gigabytes: 7), cumulativeWifi: .zero
        )
        let state = AppState(plan: PlanConfig(capGB: 20, cycleResetDay: 1),
                             snapshots: [snap], currentCycle: cycle)
        // 7 cumulative − 4 baseline = 3 GB used this cycle.
        XCTAssertEqual(calc.summary(for: state, asOf: now).used.gigabytes, 3, accuracy: 1e-9)
    }

    func testOverCapClampsRemainingAndFlagsOver() {
        let now = TestDates.date(2026, 3, 15, 12)
        let cycle = Cycle(
            start: TestDates.date(2026, 3, 1), end: TestDates.date(2026, 4, 1),
            baselineCumulativeCellular: .zero, baselineCumulativeWifi: .zero
        )
        let snap = Snapshot(
            timestamp: now, rawCellular: .zero, rawWifi: .zero,
            cumulativeCellular: DataSize(gigabytes: 13), cumulativeWifi: .zero
        )
        let state = AppState(plan: PlanConfig(capGB: 10, cycleResetDay: 1),
                             snapshots: [snap], currentCycle: cycle)
        let summary = calc.summary(for: state, asOf: now)

        XCTAssertEqual(summary.used.gigabytes, 13, accuracy: 1e-9)
        XCTAssertEqual(summary.remaining, .zero, "remaining never goes negative")
        XCTAssertTrue(summary.isOverCap)
        XCTAssertEqual(summary.fractionUsed, 1.3, accuracy: 1e-9)
        XCTAssertEqual(summary.percentUsed, 130, accuracy: 1e-9)
    }

    func testZeroCapDoesNotDivideByZero() {
        let now = TestDates.date(2026, 3, 15, 12)
        let state = AppState(plan: PlanConfig(capGB: 0, cycleResetDay: 1))
        XCTAssertEqual(calc.summary(for: state, asOf: now).fractionUsed, 0)
    }
}
