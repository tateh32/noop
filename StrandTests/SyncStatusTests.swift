import XCTest
import WhoopStore
@testable import Strand

final class SyncStatusTests: XCTestCase {

    private func utcCal() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }

    private func sleep(end: Int, json: String? = "[]") -> CachedSleepSession {
        CachedSleepSession(startTs: end - 8 * 3600, endTs: end, efficiency: 0.9,
                           restingHr: 50, avgHrv: 50, stagesJSON: json)
    }

    func testPendingRecordsIsNonNegativeGap() {
        XCTAssertEqual(SyncStatus.pendingRecords(strapNewestTs: 1_000_400, frontierTs: 1_000_000), 400)
        XCTAssertEqual(SyncStatus.pendingRecords(strapNewestTs: 1_000_000, frontierTs: 1_000_400), 0)
        XCTAssertNil(SyncStatus.pendingRecords(strapNewestTs: nil, frontierTs: 1))
        XCTAssertNil(SyncStatus.pendingRecords(strapNewestTs: 1, frontierTs: nil))
    }

    func testLastNightScoredUsesWakeDay() {
        let cal = utcCal()
        let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 9, hour: 10))!
        let end = Int(now.timeIntervalSince1970) - 3 * 3600   // 07:00 same day
        XCTAssertTrue(SyncStatus.lastNightScored(sleeps: [sleep(end: end)], days: [],
                                                 now: now, calendar: cal))
        XCTAssertFalse(SyncStatus.lastNightScored(sleeps: [sleep(end: end, json: nil)], days: [],
                                                  now: now, calendar: cal))
        let old = sleep(end: end - 3 * 86_400)
        XCTAssertFalse(SyncStatus.lastNightScored(sleeps: [old], days: [], now: now, calendar: cal))
    }

    func testLastNightScoredFallsBackToDailyMinutes() {
        let cal = utcCal()
        let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 9, hour: 10))!
        let d = DailyMetric(day: "2026-09-09", totalSleepMin: 420, efficiency: nil,
                            deepMin: nil, remMin: nil, lightMin: nil, disturbances: nil,
                            restingHr: nil, avgHrv: nil, recovery: nil, strain: nil,
                            exerciseCount: nil)
        XCTAssertTrue(SyncStatus.lastNightScored(sleeps: [], days: [d], now: now, calendar: cal))
    }

    func testLineShape() {
        let cal = utcCal()
        let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 9, hour: 10, minute: 0))!
        let synced = cal.date(from: DateComponents(year: 2026, month: 9, day: 9, hour: 7, minute: 14))!
        let s = SyncStatus.Snapshot(lastSyncedAt: synced.timeIntervalSince1970,
                                   pendingRecords: 0, lastNightScored: true, now: now)
        XCTAssertEqual(SyncStatus.line(s, calendar: cal),
                       "Offloaded 07:14 · 0 pending · last night scored")
        let none = SyncStatus.Snapshot(lastSyncedAt: nil, pendingRecords: nil,
                                        lastNightScored: false, now: now)
        XCTAssertEqual(SyncStatus.line(none, calendar: cal),
                       "Never offloaded · pending unknown · last night not scored")
    }
}
