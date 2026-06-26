import XCTest
@testable import MobileDataCore

final class FormattersTests: XCTestCase {
    func testDataUsesGigabytesAtOrAboveOneGB() {
        XCTAssertEqual(Formatters.data(DataSize(gigabytes: 1)), "1.00 GB")
        XCTAssertEqual(Formatters.data(DataSize(gigabytes: 12.34)), "12.34 GB")
    }

    func testDataUsesMegabytesBelowOneGB() {
        XCTAssertEqual(Formatters.data(DataSize(bytes: 500_000_000)), "500 MB")
        XCTAssertEqual(Formatters.data(.zero), "0 MB")
    }

    func testEurosAndPercentAndGigabytes() {
        XCTAssertEqual(Formatters.euros(3.5), "€3.50")
        XCTAssertEqual(Formatters.percent(0.367), "37%")  // rounded
        XCTAssertEqual(Formatters.gigabytes(2.0), "2.00 GB")
    }

    func testAppGroupIdentifierMatchesEntitlements() {
        // The shared store only works if this constant matches both targets'
        // entitlements; pin it so an accidental rename is caught.
        XCTAssertEqual(AppConstants.appGroupIdentifier, "group.fi.mailhub.everybytecounts")
        XCTAssertEqual(AppConstants.widgetKind, "EveryByteCountsWidget")
    }
}
