import Foundation
import Combine
import WhoopStore
import WhoopProtocol

/// Read model over the on-device WhoopStore. Opens its own handle (WAL + busy-timeout makes the
/// two-handle BLEManager+Repository pattern safe) and publishes the dashboard caches the screens bind to.
@MainActor
final class Repository: ObservableObject {
    let deviceId: String
    /// Source id for on-device computed scores (recovery/strain/sleep derived from the raw strap
    /// streams by IntelligenceEngine). Merged UNDER the imported `deviceId` rows at read time, so a
    /// real WHOOP import always wins and the strap-only user still gets a populated dashboard.
    private var computedDeviceId: String { deviceId + "-noop" }
    private var store: WhoopStore?

    /// Daily metrics (recovery/strain/sleep/HRV/RHR…) over the recent window, oldest→newest.
    @Published var days: [DailyMetric] = []
    /// Cached sleep sessions over the recent window, oldest→newest.
    @Published var sleeps: [CachedSleepSession] = []
    @Published var loaded = false

    init(deviceId: String) { self.deviceId = deviceId }

    /// The most recent *usable* day for the dashboard hero.
    ///
    /// A WHOOP export almost always ends with the in-progress cycle (today) whose
    /// recovery / HRV / strain cells are still blank. Using `days.last` then makes a
    /// successful years-long import look empty on Today. Prefer the latest day that
    /// actually has a score; fall back to the last row only when nothing is scored yet.
    var today: DailyMetric? { Self.displayDay(from: days) }

    /// Latest day with a recovery/HRV/strain/RHR value, else the last stored day.
    static func displayDay(from days: [DailyMetric]) -> DailyMetric? {
        days.last(where: {
            $0.recovery != nil || $0.avgHrv != nil || $0.strain != nil || $0.restingHr != nil
        }) ?? days.last
    }
    /// The trailing 7 days (for the week strip), oldest→newest.
    var week: [DailyMetric] { Array(days.suffix(7)) }

    /// Device-calendar `yyyy-MM-dd` for `date`. Imported WHOOP days use the cycle
    /// timezone; this is the civil date on the phone, used to keep the Today
    /// subtitle on *today* even when the latest scored cycle is older.
    static func calendarDay(of date: Date = Date()) -> String { dayString(date) }

    static func isCalendarToday(_ ymd: String) -> Bool { ymd == calendarDay() }

    /// Whole local calendar days from `ymd` until `date`. Positive means `ymd` is in the past.
    static func calendarDaysAgo(_ ymd: String, from date: Date = Date()) -> Int? {
        guard let then = civilDate(ymd) else { return nil }
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: then), to: cal.startOfDay(for: date)).day
    }

    /// Interpret `yyyy-MM-dd` as a local civil date (not UTC midnight).
    static func civilDate(_ ymd: String) -> Date? {
        let p = ymd.split(separator: "-")
        guard p.count == 3,
              let y = Int(p[0]), let m = Int(p[1]), let d = Int(p[2]) else { return nil }
        return Calendar.current.date(from: DateComponents(year: y, month: m, day: d))
    }

    static func prettyDay(_ ymd: String) -> String? {
        guard let date = civilDate(ymd) else { return nil }
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("dMMM")
        return f.string(from: date)
    }

    private func ensureStore() async -> WhoopStore? {
        if let store { return store }
        guard let path = try? StorePaths.defaultDatabasePath() else { return nil }
        let s = try? await WhoopStore(path: path)
        if let s { try? await s.upsertDevice(id: deviceId, mac: nil, name: "WHOOP") }
        store = s
        return s
    }

    /// Expose the shared store handle (used by the importer to persist mapped rows).
    func storeHandle() async -> WhoopStore? { await ensureStore() }

    /// Wipe imported and computed scores so a WHOOP / Apple Health export can be reimported
    /// cleanly. Raw BLE streams stay on disk. Refreshes the dashboard caches after.
    func clearImportedHistory() async {
        guard let store = await ensureStore() else { return }
        try? await store.clearImportedHistory()
        days = []
        sleeps = []
        loaded = false
        await refresh()
    }

    /// Checkpoint the WAL into the main DB file if the store is already open, so a file-level
    /// backup captures everything. No-op (returns false) if no handle exists yet — the caller
    /// then copies the on-disk files as-is, which still includes the -wal sidecar.
    func checkpointForBackup() async -> Bool {
        guard let store else { return false }
        do { try await store.checkpointWAL(); return true } catch { return false }
    }

    /// Reload the dashboard caches over the last `nDays`, merging imported history with the
    /// on-device computed scores so a strap-only user still gets a populated dashboard.
    func refresh(days nDays: Int = PhoneBudget.dashboardDays) async {
        guard let store = await ensureStore() else { return }
        let now = Date()
        let fromDay = Self.dayString(now.addingTimeInterval(-Double(nDays) * 86_400))
        let toDay = Self.dayString(now.addingTimeInterval(86_400))
        let nowTs = Int(now.timeIntervalSince1970)
        let lo = nowTs - nDays * 86_400, hi = nowTs + 86_400
        let sleepLimit = PhoneBudget.sleepCacheLimit

        let imported = (try? await store.dailyMetrics(deviceId: deviceId, from: fromDay, to: toDay)) ?? []
        let computed = (try? await store.dailyMetrics(deviceId: computedDeviceId, from: fromDay, to: toDay)) ?? []
        let impSleep = (try? await store.sleepSessions(deviceId: deviceId, from: lo, to: hi, limit: sleepLimit)) ?? []
        let compSleep = (try? await store.sleepSessions(deviceId: computedDeviceId, from: lo, to: hi, limit: sleepLimit)) ?? []

        self.days = Self.mergeDaily(imported: imported, computed: computed)
        self.sleeps = Self.mergeSleep(imported: impSleep, computed: compSleep)
        self.loaded = true
    }

    /// Imported daily rows win per day; computed rows fill the days the import doesn't cover.
    private static func mergeDaily(imported: [DailyMetric], computed: [DailyMetric]) -> [DailyMetric] {
        var byDay: [String: DailyMetric] = [:]
        for d in computed { byDay[d.day] = d }   // computed first…
        for d in imported { byDay[d.day] = d }   // …import overwrites, so a real WHOOP import always wins
        return byDay.values.sorted { $0.day < $1.day }
    }

    /// Same precedence for sleep sessions, keyed by the day the night ends on.
    private static func mergeSleep(imported: [CachedSleepSession], computed: [CachedSleepSession]) -> [CachedSleepSession] {
        func endDay(_ s: CachedSleepSession) -> String {
            dayString(Date(timeIntervalSince1970: TimeInterval(s.endTs)))
        }
        var byDay: [String: CachedSleepSession] = [:]
        for s in computed { byDay[endDay(s)] = s }
        for s in imported { byDay[endDay(s)] = s }
        return byDay.values.sorted { $0.startTs < $1.startTs }
    }

    // MARK: - Detail passthroughs

    func dailyMetrics(fromDay: String, toDay: String) async -> [DailyMetric] {
        guard let store = await ensureStore() else { return [] }
        return (try? await store.dailyMetrics(deviceId: deviceId, from: fromDay, to: toDay)) ?? []
    }

    func hrSamples(from: Int, to: Int, limit: Int = 8000) async -> [HRSample] {
        guard let store = await ensureStore() else { return [] }
        return (try? await store.hrSamples(deviceId: deviceId, from: from, to: to, limit: limit)) ?? []
    }

    func sleepSessions(from: Int, to: Int, limit: Int = 100) async -> [CachedSleepSession] {
        guard let store = await ensureStore() else { return [] }
        return (try? await store.sleepSessions(deviceId: deviceId, from: from, to: to, limit: limit)) ?? []
    }

    // MARK: - Metric explorer reads (generic substrate)

    /// Daily series for any metric key from a given source ("my-whoop" / "apple-health").
    func series(key: String, source: String, days: Int = 4000) async -> [(day: String, value: Double)] {
        guard let store = await ensureStore() else { return [] }
        let now = Date()
        let from = Self.dayString(now.addingTimeInterval(-Double(days) * 86_400))
        let to = Self.dayString(now.addingTimeInterval(86_400))
        let pts = (try? await store.metricSeries(deviceId: source, key: key, from: from, to: to)) ?? []
        return pts.map { ($0.day, $0.value) }
    }

    func availableKeys(source: String) async -> [String] {
        guard let store = await ensureStore() else { return [] }
        return (try? await store.metricKeys(deviceId: source)) ?? []
    }

    /// Logged behaviours (Whoop journal) for correlation insights.
    func journalEntries(days: Int = 4000) async -> [JournalEntry] {
        guard let store = await ensureStore() else { return [] }
        let now = Date()
        return (try? await store.journalEntries(
            deviceId: deviceId,
            from: Self.dayString(now.addingTimeInterval(-Double(days) * 86_400)),
            to: Self.dayString(now.addingTimeInterval(86_400)))) ?? []
    }

    /// All workouts (Whoop + Apple Health + on-device detections), newest first.
    func workoutRows(days: Int = 4000) async -> [WorkoutRow] {
        guard let store = await ensureStore() else { return [] }
        let now = Int(Date().timeIntervalSince1970)
        let lo = now - days * 86_400, hi = now + 86_400
        let imported = (try? await store.workouts(deviceId: deviceId, from: lo, to: hi, limit: 5000)) ?? []
        let apple = (try? await store.workouts(deviceId: "apple-health", from: lo, to: hi, limit: 5000)) ?? []
        let computed = (try? await store.workouts(deviceId: computedDeviceId, from: lo, to: hi, limit: 5000)) ?? []
        return Self.mergeWorkouts(imported: imported, apple: apple, computed: computed)
    }

    /// Imported WHOOP and Apple Health rows win when they overlap a strap-detected bout.
    static func mergeWorkouts(imported: [WorkoutRow], apple: [WorkoutRow],
                              computed: [WorkoutRow]) -> [WorkoutRow] {
        let preferred = imported + apple
        var out = preferred
        for row in computed where !preferred.contains(where: { workoutsOverlap($0, row) }) {
            out.append(row)
        }
        return out.sorted { $0.startTs > $1.startTs }
    }

    static func workoutsOverlap(_ a: WorkoutRow, _ b: WorkoutRow) -> Bool {
        a.startTs < b.endTs && b.startTs < a.endTs
    }

    /// Apple Health daily aggregates (steps/energy/vo2/hr).
    func appleDailyRows(days: Int = 4000) async -> [AppleDaily] {
        guard let store = await ensureStore() else { return [] }
        let now = Date()
        return (try? await store.appleDaily(
            deviceId: "apple-health",
            from: Self.dayString(now.addingTimeInterval(-Double(days) * 86_400)),
            to: Self.dayString(now.addingTimeInterval(86_400)))) ?? []
    }

    /// Shared formatter — created once. Hot read path (called per series window / refresh);
    /// allocating a DateFormatter per call was a measurable waste. Read-only use is thread-safe.
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func dayString(_ d: Date) -> String { dayFormatter.string(from: d) }
}
