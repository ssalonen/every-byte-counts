import XCTest
@testable import MobileDataCore

final class DataSizeTests: XCTestCase {
    func testGigabyteConversionIsDecimal() {
        XCTAssertEqual(DataSize(gigabytes: 1).bytes, 1_000_000_000)
        XCTAssertEqual(DataSize(bytes: 2_000_000_000).gigabytes, 2.0, accuracy: 1e-9)
    }

    func testNegativeGigabytesClampToZero() {
        XCTAssertEqual(DataSize(gigabytes: -5).bytes, 0)
    }

    func testSaturatingSubtractionNeverUnderflows() {
        let a = DataSize(bytes: 100)
        let b = DataSize(bytes: 250)
        XCTAssertEqual(a.subtractingSaturating(b), .zero)
        XCTAssertEqual(b.subtractingSaturating(a).bytes, 150)
    }

    func testComparableAndAddition() {
        XCTAssertTrue(DataSize(bytes: 10) < DataSize(bytes: 20))
        XCTAssertEqual((DataSize(bytes: 10) + DataSize(bytes: 5)).bytes, 15)
    }
}
