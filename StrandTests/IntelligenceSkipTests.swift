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
            utcDay: "2026-09-08", localDay: "2026-09-08", scored: scored))
        XCTAssertTrue(IntelligenceSkip.shouldSkip(
            utcDay: "2026-09-07", localDay: "2026-09-07", scored: scored))
    }

    func testTimezoneMismatchStillSkipsImportedDay() {
        let scored: Set<String> = ["2026-09-07"]
        XCTAssertTrue(IntelligenceSkip.shouldSkip(
            utcDay: "2026-09-08", localDay: "2026-09-07", scored: scored))
        XCTAssertTrue(IntelligenceSkip.shouldSkip(
            utcDay: "2026-09-07", localDay: "2026-09-06", scored: scored))
        XCTAssertFalse(IntelligenceSkip.shouldSkip(
            utcDay: "2026-09-08", localDay: "2026-09-08", scored: scored))
    }
}
