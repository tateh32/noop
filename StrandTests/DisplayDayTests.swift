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
}
