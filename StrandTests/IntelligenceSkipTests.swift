import XCTest
import WhoopStore
@testable import Strand

final class IntelligenceSkipTests: XCTestCase {
    private func day(_ ymd: String, recovery: Double? = nil) -> DailyMetric {
        DailyMetric(
            day: ymd, totalSleepMin: nil, efficiency: nil, deepMin: nil, remMin: nil,
            lightMin: nil, disturbances: nil, restingHr: nil, avgHrv: nil,
            recovery: recovery, strain: nil, exerciseCount: nil)
    }

    func testScoredDaysOnlyIncludesRecovery() {
        let days = [
            day("2026-09-05", recovery: 70),
            day("2026-09-06"),
            day("2026-09-07", recovery: 55),
        ]
        XCTAssertEqual(IntelligenceSkip.scoredDays(in: days), ["2026-09-05", "2026-09-07"])
    }

    func testImportYesterdayDoesNotSkipToday() {
        let scored = IntelligenceSkip.scoredDays(in: [day("2026-09-07", recovery: 81)])
        // The old all-or-nothing gate used repo.today?.recovery != nil, which would
        // skip every night after an import. Per-day skip still scores uncovered nights.
        XCTAssertFalse(IntelligenceSkip.shouldSkip(
            utcDay: "2026-09-08", localDay: "2026-09-08", scored: scored, dayOffset: 5))
        XCTAssertTrue(IntelligenceSkip.shouldSkip(
            utcDay: "2026-09-07", localDay: "2026-09-07", scored: scored, dayOffset: 5))
    }

    func testTimezoneMismatchStillSkipsImportedDay() {
        let scored: Set<String> = ["2026-09-07"]
        XCTAssertTrue(IntelligenceSkip.shouldSkip(
            utcDay: "2026-09-08", localDay: "2026-09-07", scored: scored, dayOffset: 4))
        XCTAssertTrue(IntelligenceSkip.shouldSkip(
            utcDay: "2026-09-07", localDay: "2026-09-06", scored: scored, dayOffset: 4))
        XCTAssertFalse(IntelligenceSkip.shouldSkip(
            utcDay: "2026-09-08", localDay: "2026-09-08", scored: scored, dayOffset: 4))
    }

    func testRecentNightsAlwaysRescore() {
        // A partial pass can score last night before the strap finished offloading;
        // the newest nights must stay eligible so they converge.
        let scored: Set<String> = ["2026-09-08", "2026-09-09"]
        XCTAssertFalse(IntelligenceSkip.shouldSkip(
            utcDay: "2026-09-09", localDay: "2026-09-09", scored: scored, dayOffset: 0))
        XCTAssertFalse(IntelligenceSkip.shouldSkip(
            utcDay: "2026-09-08", localDay: "2026-09-08", scored: scored, dayOffset: 1))
        XCTAssertTrue(IntelligenceSkip.shouldSkip(
            utcDay: "2026-09-08", localDay: "2026-09-08", scored: scored, dayOffset: 2))
    }
}
