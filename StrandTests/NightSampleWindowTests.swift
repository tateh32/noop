import XCTest
@testable import Strand

final class NightSampleWindowTests: XCTestCase {
    private var utc: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    func testWindowIsTwentyHoursFromSixPmToTwoPm() {
        let wake = utc.date(from: DateComponents(year: 2026, month: 9, day: 9))!
        let r = NightSampleWindow.sampleRange(wakeDayStart: wake)
        XCTAssertEqual(r.to - r.from, 20 * 3600)
        let from = Date(timeIntervalSince1970: TimeInterval(r.from))
        let to = Date(timeIntervalSince1970: TimeInterval(r.to))
        XCTAssertEqual(utc.component(.hour, from: from), 18)
        XCTAssertEqual(utc.component(.day, from: from), 8)
        XCTAssertEqual(utc.component(.hour, from: to), 14)
        XCTAssertEqual(utc.component(.day, from: to), 9)
    }

    func testWakeDaysAreLocalMidnightsNewestFirst() {
        let now = utc.date(from: DateComponents(year: 2026, month: 9, day: 9, hour: 15))!
        let days = NightSampleWindow.wakeDayStarts(now: now, count: 3, calendar: utc)
        XCTAssertEqual(days.map { NightSampleWindow.dayString($0, calendar: utc) },
                       ["2026-09-09", "2026-09-08", "2026-09-07"])
    }

    func testOldFortyTwoHourWindowWouldStartYesterdayAfternoon() {
        // Documents the bug: now-30h + LIMIT 24k ASC is not last night.
        let now = utc.date(from: DateComponents(year: 2026, month: 9, day: 9, hour: 8))!
        let oldFrom = now.addingTimeInterval(-30 * 3600)
        XCTAssertEqual(utc.component(.hour, from: oldFrom), 2)
        XCTAssertEqual(utc.component(.day, from: oldFrom), 8)
        let night = NightSampleWindow.sampleRange(wakeDayStart: utc.startOfDay(for: now))
        let nightFrom = Date(timeIntervalSince1970: TimeInterval(night.from))
        XCTAssertEqual(utc.component(.hour, from: nightFrom), 18)
    }
}
