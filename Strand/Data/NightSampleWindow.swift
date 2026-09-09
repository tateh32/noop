import Foundation

/// The on-device scorer used to take `LIMIT 24_000` samples `ORDER BY ts ASC` from
/// a 42-hour window starting 30 hours before *now*. At 1 Hz that is yesterday
/// afternoon — last night never entered `SleepStager`, so overnight wear did
/// not update Sleep.
enum NightSampleWindow {
    /// Open the window at 18:00 the evening before the wake day.
    static let eveningLeadHours = 6
    /// Close the window at 14:00 on the wake day.
    static let morningTrailHours = 14

    /// Local midnights for today, yesterday, … — the civil day each night ends on.
    static func wakeDayStarts(now: Date = Date(), count: Int,
                              calendar: Calendar = .current) -> [Date] {
        let start = calendar.startOfDay(for: now)
        return (0..<max(0, count)).compactMap { calendar.date(byAdding: .day, value: -$0, to: start) }
    }

    /// `[18:00 previous, 14:00 wake day]` as unix seconds.
    static func sampleRange(wakeDayStart: Date) -> (from: Int, to: Int) {
        let from = wakeDayStart.addingTimeInterval(TimeInterval(-eveningLeadHours * 3600))
        let to = wakeDayStart.addingTimeInterval(TimeInterval(morningTrailHours * 3600))
        return (Int(from.timeIntervalSince1970), Int(to.timeIntervalSince1970))
    }

    static func dayString(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
