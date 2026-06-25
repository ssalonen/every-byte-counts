import XCTest
@testable import MobileDataCore

final class CostStrategyTests: XCTestCase {
    func testFlatRateChargesExcessOnly() {
        let s = FlatRateCostStrategy(eurPerGB: 5)
        XCTAssertEqual(s.estimate(excessGB: 3).amountEUR, 15, accuracy: 1e-9)
        XCTAssertEqual(s.estimate(excessGB: 0).amountEUR, 0)
        XCTAssertEqual(s.estimate(excessGB: -2).amountEUR, 0) // clamped
    }

    func testSteppedRoundsUpToWholeBlocks() {
        let s = SteppedCostStrategy(blockGB: 1, eurPerBlock: 6)
        XCTAssertEqual(s.estimate(excessGB: 0.2).amountEUR, 6, accuracy: 1e-9)  // 1 block
        XCTAssertEqual(s.estimate(excessGB: 2.1).amountEUR, 18, accuracy: 1e-9) // 3 blocks
    }

    func testThrottleIsAlwaysFree() {
        XCTAssertEqual(ThrottleCostStrategy().estimate(excessGB: 99).amountEUR, 0)
    }

    func testFactoryMapsConfigToStrategy() {
        XCTAssertEqual(CostStrategyFactory.strategy(for: .flatRate(eurPerGB: 2)).estimate(excessGB: 4).amountEUR, 8, accuracy: 1e-9)
        XCTAssertEqual(CostStrategyFactory.strategy(for: .throttle).estimate(excessGB: 4).amountEUR, 0)
        XCTAssertEqual(CostStrategyFactory.strategy(for: .stepped(blockGB: 2, eurPerBlock: 10)).estimate(excessGB: 3).amountEUR, 20, accuracy: 1e-9)
    }
}
