import Foundation
import WhoopStore

/// One-line trusted sync status for Today. Pure so Today can pass repo +
/// offload fields without observing live heart rate.
enum SyncStatus {

    struct Snapshot: Equatable {
        var lastSyncedAt: TimeInterval?
        var pendingRecords: Int?
        var lastNightScored: Bool
        var now: Date
    }

    /// 1 Hz approximation: strap newest unix minus our HR frontier.
    static func pendingRecords(strapNewestTs: Int?, frontierTs: Int?) -> Int? {
        guard let newest = strapNewestTs, let frontier = frontierTs else { return nil }
        return max(0, newest - frontier)
    }

    /// Last night = the sleep whose wake civil day is the current NightSampleWindow
    /// wake day (today's date, the night that ended this morning).
    static func lastNightScored(sleeps: [CachedSleepSession], days: [DailyMetric],
                                now: Date, calendar: Calendar = .current) -> Bool {
        guard let wake = NightSampleWindow.wakeDayStarts(now: now, count: 1,
                                                          calendar: calendar).first else {
            return false
        }
        let ymd = NightSampleWindow.dayString(wake, calendar: calendar)
        if sleeps.contains(where: {
            NightSampleWindow.dayString(Date(timeIntervalSince1970: TimeInterval($0.endTs)),
                                         calendar: calendar) == ymd
                && $0.stagesJSON != nil
        }) { return true }
        return days.contains { $0.day == ymd && $0.totalSleepMin != nil }
    }

    static func line(_ s: Snapshot, calendar: Calendar = .current) -> String {
        let offload = offloadPhrase(s.lastSyncedAt, now: s.now, calendar: calendar)
        let pending = pendingPhrase(s.pendingRecords)
        let night = s.lastNightScored ? "last night scored" : "last night not scored"
        return "\(offload) · \(pending) · \(night)"
    }

    private static func offloadPhrase(_ ts: TimeInterval?, now: Date,
                                      calendar: Calendar) -> String {
        guard let ts else { return "Never offloaded" }
        let date = Date(timeIntervalSince1970: ts)
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        if calendar.isDate(date, inSameDayAs: now) {
            f.dateFormat = "HH:mm"
            return "Offloaded \(f.string(from: date))"
        }
        f.dateFormat = "d MMM HH:mm"
        return "Offloaded \(f.string(from: date))"
    }

    private static func pendingPhrase(_ n: Int?) -> String {
        guard let n else { return "pending unknown" }
        if n == 0 { return "0 pending" }
        if n >= 1000 {
            let k = Double(n) / 1000.0
            return String(format: "%.1fk pending", k)
        }
        return "\(n) pending"
    }
}
