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
        XCTAssertGreaterThan(PhoneBudget.dashboardDays, 30)
        XCTAssertGreaterThan(PhoneBudget.sleepCacheLimit, 7)
    }

    func testMacKeepsTheWideWindow() {
        #if os(iOS)
        XCTAssertTrue(PhoneBudget.isPhone)
        XCTAssertEqual(PhoneBudget.intelligenceDays, 3)
        XCTAssertEqual(PhoneBudget.intelligenceSampleLimit, 80_000)
        XCTAssertEqual(PhoneBudget.heatStripMaxDays, 180)
        XCTAssertEqual(PhoneBudget.dashboardDays, 400)
        #else
        XCTAssertFalse(PhoneBudget.isPhone)
        XCTAssertEqual(PhoneBudget.intelligenceDays, 21)
        XCTAssertEqual(PhoneBudget.heatStripMaxDays, 4000)
        XCTAssertEqual(PhoneBudget.intelligenceSampleLimit, 200_000)
        XCTAssertEqual(PhoneBudget.dashboardDays, 4000)
        #endif
    }
}
