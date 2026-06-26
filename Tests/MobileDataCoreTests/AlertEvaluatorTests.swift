import XCTest
@testable import MobileDataCore

final class AlertEvaluatorTests: XCTestCase {
    let eval = AlertEvaluator()
    let cycleID = UUID()

    func testFiresThresholdsAtOrBelowCurrentUsage() {
        let r = eval.evaluate(fractionUsed: 0.82, thresholds: [0.5, 0.8, 1.0], cycleID: cycleID, state: .empty)
        XCTAssertEqual(r.alerts.map(\.threshold), [0.5, 0.8])
        XCTAssertEqual(r.state.firedThresholds, [0.5, 0.8])
    }

    func testDoesNotRefireAlreadyFiredThresholds() {
        let first = eval.evaluate(fractionUsed: 0.55, thresholds: [0.5, 0.8, 1.0], cycleID: cycleID, state: .empty)
        let second = eval.evaluate(fractionUsed: 0.60, thresholds: [0.5, 0.8, 1.0], cycleID: cycleID, state: first.state)
        XCTAssertTrue(second.alerts.isEmpty)
    }

    func testNewThresholdFiresOnLaterCrossing() {
        let first = eval.evaluate(fractionUsed: 0.55, thresholds: [0.5, 0.8, 1.0], cycleID: cycleID, state: .empty)
        let second = eval.evaluate(fractionUsed: 0.85, thresholds: [0.5, 0.8, 1.0], cycleID: cycleID, state: first.state)
        XCTAssertEqual(second.alerts.map(\.threshold), [0.8])
    }

    func testCycleChangeResetsFiredSet() {
        let first = eval.evaluate(fractionUsed: 0.9, thresholds: [0.5, 0.8], cycleID: cycleID, state: .empty)
        XCTAssertEqual(first.alerts.count, 2)
        // New cycle id → thresholds may fire again.
        let newCycle = UUID()
        let second = eval.evaluate(fractionUsed: 0.6, thresholds: [0.5, 0.8], cycleID: newCycle, state: first.state)
        XCTAssertEqual(second.alerts.map(\.threshold), [0.5])
    }

    func test100PercentAlertHasCapReachedCopy() {
        let r = eval.evaluate(fractionUsed: 1.0, thresholds: [1.0], cycleID: cycleID, state: .empty)
        XCTAssertEqual(r.alerts.first?.title, "Data cap reached")
    }
}
