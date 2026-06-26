import XCTest
@testable import MobileDataCore

final class PlanConfigTests: XCTestCase {
    func testResetDayIsClampedToValidRange() {
        // A reset day must always be a real day-of-month selector (1...31).
        XCTAssertEqual(PlanConfig(capGB: 10, cycleResetDay: 0).cycleResetDay, 1)
        XCTAssertEqual(PlanConfig(capGB: 10, cycleResetDay: 99).cycleResetDay, 31)
        XCTAssertEqual(PlanConfig(capGB: 10, cycleResetDay: 15).cycleResetDay, 15)
    }

    func testThresholdsAreStoredSorted() {
        // AlertEvaluator relies on ascending thresholds to fire in order.
        let plan = PlanConfig(capGB: 10, cycleResetDay: 1, alertThresholds: [1.0, 0.5, 0.8])
        XCTAssertEqual(plan.alertThresholds, [0.5, 0.8, 1.0])
    }

    func testCapConvertsGigabytesToBytes() {
        XCTAssertEqual(PlanConfig(capGB: 20, cycleResetDay: 1).cap.bytes, 20_000_000_000)
    }

    func testDefaultsAreReasonable() {
        let d = PlanConfig.default
        XCTAssertEqual(d.capGB, 20)
        XCTAssertEqual(d.cycleResetDay, 1)
        XCTAssertEqual(d.alertThresholds, [0.5, 0.8, 1.0])
        if case let .flatRate(rate) = d.costModel {
            XCTAssertGreaterThan(rate, 0)
        } else {
            XCTFail("Default cost model should be flat rate")
        }
    }
}
