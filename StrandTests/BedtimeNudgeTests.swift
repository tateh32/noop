import XCTest
import WhoopStore
@testable import Strand

final class BedtimeNudgeTests: XCTestCase {

    private func utcCal() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }

    private func day(_ ymd: String, asleep: Double?) -> DailyMetric {
        DailyMetric(day: ymd, totalSleepMin: asleep, efficiency: nil, deepMin: nil,
                     remMin: nil, lightMin: nil, disturbances: nil, restingHr: nil,
                     avgHrv: nil, recovery: nil, strain: nil, exerciseCount: nil)
    }

    func testNeedIsAtLeastSevenAndAHalfHours() {
        XCTAssertEqual(BedtimeNudge.sleepNeedMin(typicalAsleepMin: nil), 450)
        XCTAssertEqual(BedtimeNudge.sleepNeedMin(typicalAsleepMin: 400), 450)
        XCTAssertEqual(BedtimeNudge.sleepNeedMin(typicalAsleepMin: 480), 480)
    }

    func testDebtSumsRecentShortNights() {
        let days = [
            day("2026-09-07", asleep: 450),
            day("2026-09-08", asleep: 390),   // 60 min debt vs 450
            day("2026-09-09", asleep: 420),   // 30 min debt
        ]
        XCTAssertEqual(BedtimeNudge.debtMin(days: days, needMin: 450, nights: 2), 90)
    }

    func testZeroDebt() {
        let days = [day("2026-09-08", asleep: 480), day("2026-09-09", asleep: 500)]
        XCTAssertEqual(BedtimeNudge.debtMin(days: days, needMin: 450, nights: 2), 0)
    }

    func testBlankNightsDoNotInventDebt() {
        let days = [day("2026-09-08", asleep: nil), day("2026-09-09", asleep: 450)]
        XCTAssertEqual(BedtimeNudge.debtMin(days: days, needMin: 450, nights: 2), 0)
    }

    func testSuggestedBedtimeFromDebt() {
        let cal = utcCal()
        let wake = cal.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 7, minute: 0))!
        // need 450 + debt 40 = 490 min = 8h10m before 07:00 → 22:50
        let bed = BedtimeNudge.suggestedBedtime(wake: wake, needMin: 450, debtMin: 40)
        XCTAssertEqual(cal.component(.hour, from: bed), 22)
        XCTAssertEqual(cal.component(.minute, from: bed), 50)
    }

    func testLineNamesDebtBedtime() {
        let cal = utcCal()
        let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 9, hour: 18))!
        let days = [day("2026-09-08", asleep: 390), day("2026-09-09", asleep: 390)]
        let line = BedtimeNudge.line(now: now, wakeMinutes: 7 * 60, days: days, calendar: cal)
        XCTAssertTrue(line.hasPrefix("To clear your debt, be in bed by "))
        XCTAssertTrue(line.contains("22:"))
    }

    func testZeroDebtLineIsQuiet() {
        let cal = utcCal()
        let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 9, hour: 18))!
        let days = [day("2026-09-08", asleep: 480), day("2026-09-09", asleep: 480)]
        let line = BedtimeNudge.line(now: now, wakeMinutes: 7 * 60, days: days, calendar: cal)
        XCTAssertEqual(line, "Be in bed by 23:30 to hit your need.")
    }

    func testTimezoneShiftsTheAbsoluteInstantNotTheClock() {
        var la = Calendar(identifier: .gregorian)
        la.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        var utc = utcCal()
        let nowLA = la.date(from: DateComponents(year: 2026, month: 9, day: 9, hour: 18))!
        let nowUTC = utc.date(from: DateComponents(year: 2026, month: 9, day: 9, hour: 18))!
        let days = [day("2026-09-09", asleep: 450)]
        let lineLA = BedtimeNudge.line(now: nowLA, wakeMinutes: 7 * 60, days: days, calendar: la)
        let lineUTC = BedtimeNudge.line(now: nowUTC, wakeMinutes: 7 * 60, days: days, calendar: utc)
        // Same local clock (23:30) in both zones.
        XCTAssertEqual(lineLA, lineUTC)
        let wakeLA = BedtimeNudge.nextWake(minutesFromMidnight: 7 * 60, now: nowLA, calendar: la)
        let wakeUTC = BedtimeNudge.nextWake(minutesFromMidnight: 7 * 60, now: nowUTC, calendar: utc)
        XCTAssertNotEqual(wakeLA.timeIntervalSince1970, wakeUTC.timeIntervalSince1970)
    }
}
