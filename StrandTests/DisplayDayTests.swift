import XCTest
import WhoopStore
@testable import Strand

final class DisplayDayTests: XCTestCase {
    private func day(_ ymd: String, recovery: Double? = nil, hrv: Double? = nil,
                     strain: Double? = nil, rhr: Int? = nil) -> DailyMetric {
        DailyMetric(
            day: ymd, totalSleepMin: nil, efficiency: nil, deepMin: nil, remMin: nil,
            lightMin: nil, disturbances: nil, restingHr: rhr, avgHrv: hrv,
            recovery: recovery, strain: strain, exerciseCount: nil)
    }

    func testEmpty() {
        XCTAssertNil(Repository.displayDay(from: []))
    }

    func testSkipsUnscoredTrailingCycle() {
        let scored = day("2026-09-06", recovery: 72, hrv: 54)
        let open = day("2026-09-07")
        XCTAssertEqual(Repository.displayDay(from: [scored, open])?.day, "2026-09-06")
    }

    func testFallsBackToLastWhenNothingScored() {
        let a = day("2026-09-05")
        let b = day("2026-09-06")
        XCTAssertEqual(Repository.displayDay(from: [a, b])?.day, "2026-09-06")
    }

    func testUsesLatestScoredEvenIfOlderRowsExist() {
        let old = day("2026-01-01", recovery: 40)
        let mid = day("2026-09-05", recovery: 81, strain: 8.2)
        let open = day("2026-09-06")
        XCTAssertEqual(Repository.displayDay(from: [old, mid, open])?.day, "2026-09-05")
    }

    func testCivilDateIsLocalCalendarNotUTCMidnight() {
        let date = Repository.civilDate("2026-04-08")
        XCTAssertNotNil(date)
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date!)
        XCTAssertEqual(c.year, 2026)
        XCTAssertEqual(c.month, 4)
        XCTAssertEqual(c.day, 8)
    }

    func testCalendarDaysAgoCountsLocalDays() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let from = cal.date(from: DateComponents(year: 2026, month: 9, day: 8))!
        XCTAssertEqual(Repository.calendarDaysAgo("2026-04-08", from: from), 153)
        XCTAssertEqual(Repository.calendarDaysAgo("2026-09-07", from: from), 1)
        XCTAssertEqual(Repository.calendarDaysAgo("2026-09-08", from: from), 0)
        XCTAssertTrue(Repository.isCalendarToday(Repository.calendarDay()))
    }
}
