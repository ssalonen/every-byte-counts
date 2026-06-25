import XCTest
@testable import MobileDataCore

final class DailyAggregatorTests: XCTestCase {
    let agg = DailyAggregator(calendar: TestDates.calendar)

    private func snapshot(_ date: Date, cumulative: UInt64) -> Snapshot {
        Snapshot(
            timestamp: date,
            rawCellular: DataSize(bytes: cumulative),
            rawWifi: .zero,
            cumulativeCellular: DataSize(bytes: cumulative),
            cumulativeWifi: .zero
        )
    }

    func testSingleDayDelta() {
        let snaps = [
            snapshot(TestDates.date(2026, 3, 10, 9), cumulative: 0),
            snapshot(TestDates.date(2026, 3, 10, 17), cumulative: GB)
        ]
        let totals = agg.dailyTotals(from: snaps)
        XCTAssertEqual(totals.count, 1)
        XCTAssertEqual(totals[0].date, TestDates.date(2026, 3, 10, 0, 0))
        XCTAssertEqual(totals[0].cellular.bytes, GB)
    }

    func testDeltaSplitAcrossMidnightProportionally() {
        // 1 GB used evenly between 22:00 and 02:00 → 2h before midnight, 2h after,
        // so 0.5 GB lands on each day.
        let snaps = [
            snapshot(TestDates.date(2026, 3, 10, 22), cumulative: 0),
            snapshot(TestDates.date(2026, 3, 11, 2), cumulative: GB)
        ]
        let totals = agg.dailyTotals(from: snaps)
        XCTAssertEqual(totals.count, 2)
        XCTAssertEqual(Double(totals[0].cellular.bytes), Double(GB) * 0.5, accuracy: Double(GB) * 0.01)
        XCTAssertEqual(Double(totals[1].cellular.bytes), Double(GB) * 0.5, accuracy: Double(GB) * 0.01)
    }

    func testDayFractionsSumToOne() {
        let fractions = agg.dayFractions(from: TestDates.date(2026, 3, 10, 18), to: TestDates.date(2026, 3, 13, 6))
        let sum = fractions.reduce(0) { $0 + $1.fraction }
        XCTAssertEqual(sum, 1.0, accuracy: 1e-9)
        XCTAssertEqual(fractions.count, 4) // spans days 10,11,12,13
    }

    func testFewerThanTwoSnapshotsYieldsNothing() {
        XCTAssertTrue(agg.dailyTotals(from: []).isEmpty)
        XCTAssertTrue(agg.dailyTotals(from: [snapshot(TestDates.date(2026, 3, 10), cumulative: 0)]).isEmpty)
    }

    func testRangeFiltersOutsideDays() {
        let snaps = [
            snapshot(TestDates.date(2026, 3, 9, 12), cumulative: 0),
            snapshot(TestDates.date(2026, 3, 10, 12), cumulative: GB),
            snapshot(TestDates.date(2026, 3, 11, 12), cumulative: 2 * GB)
        ]
        let range = (TestDates.date(2026, 3, 10, 0, 0), TestDates.date(2026, 3, 11, 0, 0))
        let totals = agg.dailyTotals(from: snaps, in: range)
        XCTAssertEqual(totals.count, 1)
        XCTAssertEqual(totals[0].date, TestDates.date(2026, 3, 10, 0, 0))
    }
}
