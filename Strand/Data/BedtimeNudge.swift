import Foundation
import WhoopStore

/// Pure bedtime math: sleep need (max 7.5h, typical asleep) plus recent debt
/// → a suggested lights-out so tonight clears the debt before wake.
enum BedtimeNudge {
    static let floorNeedMin: Double = 450   // 7.5 h

    static func sleepNeedMin(typicalAsleepMin: Double?) -> Double {
        max(floorNeedMin, typicalAsleepMin ?? floorNeedMin)
    }

    static func typicalAsleepMin(days: [DailyMetric]) -> Double? {
        let vals = days.compactMap(\.totalSleepMin).filter { $0 > 0 }
        guard !vals.isEmpty else { return nil }
        return vals.reduce(0, +) / Double(vals.count)
    }

    /// Per-night debt floored at 0, summed over the trailing `nights` that have
    /// an asleep value. Nights with no sleep data do not add debt (unknown ≠ short).
    static func debtMin(days: [DailyMetric], needMin: Double, nights: Int = 2) -> Double {
        let recent = days.suffix(max(0, nights))
        var sum = 0.0
        for d in recent {
            guard let asleep = d.totalSleepMin, asleep > 0 else { continue }
            sum += max(0, needMin - asleep)
        }
        return sum
    }

    static func nextWake(minutesFromMidnight: Int, now: Date,
                         calendar: Calendar = .current) -> Date {
        SmartWake.nextTargetWake(minutesFromMidnight: minutesFromMidnight,
                                  now: now, calendar: calendar)
    }

    static func suggestedBedtime(wake: Date, needMin: Double, debtMin: Double) -> Date {
        wake.addingTimeInterval(-(max(0, needMin) + max(0, debtMin)) * 60)
    }

    static func timeString(_ date: Date, calendar: Calendar = .current) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    /// One quiet line. Zero debt still names a bedtime so the user has a target;
    /// with debt the copy is "to clear your debt".
    static func line(now: Date, wakeMinutes: Int, days: [DailyMetric],
                     calendar: Calendar = .current) -> String {
        let need = sleepNeedMin(typicalAsleepMin: typicalAsleepMin(days: days))
        let debt = debtMin(days: days, needMin: need)
        let wake = nextWake(minutesFromMidnight: wakeMinutes, now: now, calendar: calendar)
        let bed = suggestedBedtime(wake: wake, needMin: need, debtMin: debt)
        let clock = timeString(bed, calendar: calendar)
        if debt < 1 {
            return "Be in bed by \(clock) to hit your need."
        }
        return "To clear your debt, be in bed by \(clock)."
    }
}
