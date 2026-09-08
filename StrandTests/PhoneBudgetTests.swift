import XCTest
@testable import Strand

final class PhoneBudgetTests: XCTestCase {
    func testCapsAreSane() {
        XCTAssertGreaterThan(PhoneBudget.intelligenceDays, 0)
        XCTAssertLessThanOrEqual(PhoneBudget.intelligenceDays, 21)
        XCTAssertGreaterThan(PhoneBudget.intelligenceSampleLimit, 200)
        XCTAssertLessThanOrEqual(PhoneBudget.intelligenceSampleLimit, 200_000)
        XCTAssertGreaterThan(PhoneBudget.chartMaxPoints, 2)
        XCTAssertGreaterThan(PhoneBudget.heatStripMaxDays, 30)
        XCTAssertGreaterThan(PhoneBudget.liveLogCap, 10)
        XCTAssertGreaterThan(PhoneBudget.sparkQueryDays, 14)
    }

    func testMacKeepsTheWideWindow() {
        #if os(iOS)
        XCTAssertTrue(PhoneBudget.isPhone)
        XCTAssertEqual(PhoneBudget.intelligenceDays, 3)
        XCTAssertEqual(PhoneBudget.heatStripMaxDays, 366)
        #else
        XCTAssertFalse(PhoneBudget.isPhone)
        XCTAssertEqual(PhoneBudget.intelligenceDays, 21)
        XCTAssertEqual(PhoneBudget.heatStripMaxDays, 4000)
        XCTAssertEqual(PhoneBudget.intelligenceSampleLimit, 200_000)
        #endif
    }
}
