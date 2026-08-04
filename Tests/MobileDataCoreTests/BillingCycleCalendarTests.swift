import XCTest
@testable import MobileDataCore

final class BillingCycleCalendarTests: XCTestCase {
    let cal = BillingCycleCalendar(calendar: TestDates.calendar)

    func testBoundsWhenAfterResetDay() {
        // Reset day 1; on the 15th the cycle runs 1st → 1st of next month.
        let (start, end) = cal.cycleBounds(containing: TestDates.date(2026, 3, 15), resetDay: 1)
        XCTAssertEqual(start, TestDates.date(2026, 3, 1, 0, 0))
        XCTAssertEqual(end, TestDates.date(2026, 4, 1, 0, 0))
    }

    func testBoundsWhenBeforeResetDay() {
        // Reset day 20; on the 5th we're still in the cycle that began last month.
        let (start, end) = cal.cycleBounds(containing: TestDates.date(2026, 3, 5), resetDay: 20)
        XCTAssertEqual(start, TestDates.date(2026, 2, 20, 0, 0))
        XCTAssertEqual(end, TestDates.date(2026, 3, 20, 0, 0))
    }

    func testResetDayClampedToShortMonth() {
        // Reset day 31; February has no 31st, so the cycle resets on Feb 28 (2026).
        let (start, end) = cal.cycleBounds(containing: TestDates.date(2026, 2, 15), resetDay: 31)
        XCTAssertEqual(start, TestDates.date(2026, 1, 31, 0, 0))
        XCTAssertEqual(end, TestDates.date(2026, 2, 28, 0, 0))
    }

    func testDaysRemainingAndElapsed() {
        // Reset day 1; on March 10 (noon): elapsed = 10 (1st..10th inclusive),
        // remaining counts today through the 31st → 22 days until April 1.
        let date = TestDates.date(2026, 3, 10)
        XCTAssertEqual(cal.daysElapsed(in: date, resetDay: 1), 10)
        XCTAssertEqual(cal.daysRemaining(in: date, resetDay: 1), 22)
    }

    func testDaysRemainingAtLeastOne() {
        // On the very last day of the cycle there's still 1 day remaining.
        let date = TestDates.date(2026, 3, 31, 23, 0)
        XCTAssertGreaterThanOrEqual(cal.daysRemaining(in: date, resetDay: 1), 1)
    }

    func testBoundsClampedToNotOverlapThePreviousCycle() {
        // Reset day 20 would put the window back at 20 Feb, but a cycle already
        // closed on 1 Mar — the open one can only start where that ended.
        let (start, end) = cal.cycleBounds(
            containing: TestDates.date(2026, 3, 5), resetDay: 20,
            notBefore: TestDates.date(2026, 3, 1, 0, 0))
        XCTAssertEqual(start, TestDates.date(2026, 3, 1, 0, 0))
        XCTAssertEqual(end, TestDates.date(2026, 3, 20, 0, 0))
    }

    func testBoundsIgnoreANotBeforeOutsideTheWindow() {
        // A previous cycle that ended before this window opened (or after it
        // closes) says nothing about where this one starts.
        let window = (start: TestDates.date(2026, 3, 1, 0, 0), end: TestDates.date(2026, 4, 1, 0, 0))
        for notBefore in [TestDates.date(2026, 1, 1, 0, 0), window.start, TestDates.date(2026, 5, 1, 0, 0)] {
            let bounds = cal.cycleBounds(
                containing: TestDates.date(2026, 3, 15), resetDay: 1, notBefore: notBefore)
            XCTAssertEqual(bounds.start, window.start)
            XCTAssertEqual(bounds.end, window.end)
        }
        let unbounded = cal.cycleBounds(containing: TestDates.date(2026, 3, 15), resetDay: 1, notBefore: nil)
        XCTAssertEqual(unbounded.start, window.start)
    }

    func testDaysCountedAgainstAnExplicitWindow() {
        // A cycle clamped to 10 Mar … 1 Apr: on the 15th that's day 6 of the
        // cycle with 17 days (the 15th through the 31st) still to run.
        let date = TestDates.date(2026, 3, 15)
        XCTAssertEqual(cal.daysElapsed(in: date, cycleStart: TestDates.date(2026, 3, 10, 0, 0)), 6)
        XCTAssertEqual(cal.daysRemaining(in: date, cycleEnd: TestDates.date(2026, 4, 1, 0, 0)), 17)
    }
}
