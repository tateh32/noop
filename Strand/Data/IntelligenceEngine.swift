import Foundation
import Combine
import WhoopProtocol
import WhoopStore
import StrandAnalytics

/// On-device "intelligence": computes recovery / day-strain / sleep from the raw strap streams using
/// the same model shape WHOOP uses (HRV vs personal baseline ~60%, resting HR ~20%, sleep ~15%,
/// respiration ~5%; strain 0–21 from cardiovascular load). This is what makes NOOP independent of
/// WHOOP's cloud — for any day the strap collected raw data with NOOP connected, NOOP scores it
/// itself rather than relying on the values WHOOP computed in the imported CSV.
@MainActor
final class IntelligenceEngine: ObservableObject {
    private let repo: Repository
    private let profile: ProfileStore
    private let deviceId: String

    @Published var results: [Computed] = []      // newest first
    @Published var computing = false
    @Published var note: String?

    /// The in-flight scoring pass, if any. See `analyzeRecent`.
    private var analyzeTask: Task<Void, Never>?

    struct Computed: Identifiable {
        let day: String
        let recovery: Double?
        let strain: Double?
        let sleepMin: Double?
        let hrv: Double?
        let rhr: Int?
        var id: String { day }
    }

    init(repo: Repository, profile: ProfileStore, deviceId: String) {
        self.repo = repo; self.profile = profile; self.deviceId = deviceId
    }

    /// Compute on-device scores for each of the last `maxDays` that actually has raw HR data.
    /// Personal baselines (HRV / resting HR) are folded from the imported history, so even the first
    /// live night can be scored against your norm.
    ///
    /// Heavy sleep-staging runs off the main actor. On iPhone we score fewer nights and cap the
    /// per-stream sample count so a 14-day BLE offload cannot jetsam the process.
    /// Serializes callers. Four independent triggers exist (launch loop, foreground,
    /// offload-complete, the Intelligence screen); without this they ran overlapping
    /// passes, each holding several nights of 1 Hz streams — enough to get the app
    /// killed on an iPhone. A caller that arrives mid-pass awaits the in-flight one.
    func analyzeRecent(maxDays: Int = PhoneBudget.intelligenceDays) async {
        if let inFlight = analyzeTask {
            await inFlight.value
            return
        }
        let task = Task { await analyzeRecentImpl(maxDays: maxDays) }
        analyzeTask = task
        await task.value
        analyzeTask = nil
    }

    private func analyzeRecentImpl(maxDays: Int) async {
        guard let store = await repo.storeHandle() else { note = "No on-device store yet."; return }
        guard let hrvCfg = Baselines.metricCfg["hrv"],
              let rhrCfg = Baselines.metricCfg["resting_hr"] else { return }

        computing = true
        defer { computing = false }

        let up = UserProfile(weightKg: profile.weightKg, heightCm: profile.heightCm,
                             age: Double(profile.age), sex: profile.sex)

        // Baselines from the imported nightly history (ascending). foldHistory winsorizes outliers.
        let hist = repo.days
        let hrvBase = Baselines.foldHistory(hist.map { $0.avgHrv }, cfg: hrvCfg)
        let rhrBase = Baselines.foldHistory(hist.map { $0.restingHr.map(Double.init) }, cfg: rhrCfg)
        let baselines = AnalyticsEngine.ProfileBaselines(hrv: hrvBase, restingHR: rhrBase)

        let maxHR = profile.hrMaxOverride > 0 ? Double(profile.hrMaxOverride) : nil
        let tz = TimeZone.current
        var out: [Computed] = []
        var dailies: [DailyMetric] = []
        var cachedSleep: [CachedSleepSession] = []
        var detectedWorkouts: [WorkoutRow] = []
        let sampleLimit = PhoneBudget.intelligenceSampleLimit
        // Skip nights that already have a recovery score (WHOOP import or a prior
        // pass). Do not bail out of the whole loop — `repo.today` is the latest
        // *scored* day, often yesterday after an import, and skipping everything
        // would leave new strap nights unscored on iPhone.
        let alreadyScored = PhoneBudget.skipScoringWhenImported
            ? IntelligenceSkip.scoredDays(in: hist) : []

        let wakeStarts = NightSampleWindow.wakeDayStarts(count: maxDays)
        for (offset, wakeStart) in wakeStarts.enumerated() {
            let day = NightSampleWindow.dayString(wakeStart)
            let utcDay = AnalyticsEngine.dayString(Int(wakeStart.timeIntervalSince1970) + 12 * 3_600)
            if PhoneBudget.skipScoringWhenImported {
                if IntelligenceSkip.shouldSkip(utcDay: utcDay, localDay: day,
                                               scored: alreadyScored, dayOffset: offset) {
                    continue
                }
            }
            // 18:00 previous → 14:00 wake day, so LIMIT N is the night, not yesterday afternoon.
            let window = NightSampleWindow.sampleRange(wakeDayStart: wakeStart)
            let from = window.from
            let to = window.to

            let hr = (try? await store.hrSamples(deviceId: deviceId, from: from, to: to, limit: sampleLimit)) ?? []
            guard hr.count >= 200 else { continue }   // need real raw data, not a stray sample
            let rr = (try? await store.rrIntervals(deviceId: deviceId, from: from, to: to, limit: sampleLimit)) ?? []
            let resp = (try? await store.respSamples(deviceId: deviceId, from: from, to: to, limit: sampleLimit)) ?? []
            let grav = (try? await store.gravitySamples(deviceId: deviceId, from: from, to: to, limit: sampleLimit)) ?? []

            let res = await Self.analyzeDayOffMain(day: day, hr: hr, rr: rr, resp: resp, gravity: grav,
                                                   profile: up, baselines: baselines, maxHROverride: maxHR,
                                                   timeZone: tz)
            out.append(Computed(day: day, recovery: res.recovery, strain: res.strain,
                                sleepMin: res.daily.totalSleepMin, hrv: res.daily.avgHrv,
                                rhr: res.daily.restingHr))
            dailies.append(res.daily)
            cachedSleep.append(contentsOf: res.cachedSleep)
            detectedWorkouts.append(contentsOf: Self.workoutRows(from: res.workouts))
            await Task.yield()
        }

        // Persist the computed scores under a dedicated "-noop" source so the WHOLE dashboard
        // (Today / Recovery / Strain / Sleep / Trends), not just this screen, reads them. The
        // Repository merges these UNDER any imported "my-whoop" rows, so a real WHOOP import
        // always wins; this only fills the days the strap collected but no import covered.
        let computedId = deviceId + "-noop"
        if !dailies.isEmpty { _ = try? await store.upsertDailyMetrics(dailies, deviceId: computedId) }
        if !cachedSleep.isEmpty { _ = try? await store.upsertSleepSessions(cachedSleep, deviceId: computedId) }
        if !detectedWorkouts.isEmpty { _ = try? await store.upsertWorkouts(detectedWorkouts, deviceId: computedId) }

        results = out
        note = out.isEmpty && alreadyScored.isEmpty
            ? "No scored nights yet. Wear the strap with NOOP connected overnight and the engine will score your recovery, strain and sleep itself, no WHOOP cloud required."
            : nil

        // Reload the dashboard caches so the freshly computed scores show up immediately.
        if !dailies.isEmpty { await repo.refresh() }
    }

    /// Sleep staging a night of 1 Hz samples is CPU-heavy; never run it on the main actor.
    private static func analyzeDayOffMain(
        day: String, hr: [HRSample], rr: [RRInterval],
        resp: [RespSample], gravity: [GravitySample],
        profile: UserProfile, baselines: AnalyticsEngine.ProfileBaselines,
        maxHROverride: Double?,
        timeZone: TimeZone
    ) async -> AnalyticsEngine.DayResult {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                let result = AnalyticsEngine.analyzeDay(
                    day: day, hr: hr, rr: rr, resp: resp, gravity: gravity,
                    profile: profile, baselines: baselines, maxHROverride: maxHROverride,
                    timeZone: timeZone)
                cont.resume(returning: result)
            }
        }
    }

    /// Map detector bouts into the same cache shape WHOOP / Apple Health imports use.
    static func workoutRows(from sessions: [ExerciseSession]) -> [WorkoutRow] {
        sessions.map { s in
            let zjson: String?
            if s.zoneTimePct.isEmpty {
                zjson = nil
            } else {
                let obj = Dictionary(uniqueKeysWithValues: s.zoneTimePct.map { ("z\($0.key)", $0.value) })
                zjson = (try? JSONSerialization.data(withJSONObject: obj))
                    .flatMap { String(data: $0, encoding: .utf8) }
            }
            return WorkoutRow(
                startTs: s.start, endTs: s.end, sport: "Workout", source: "noop",
                durationS: s.durationS, energyKcal: s.caloriesKcal,
                avgHr: Int(s.avgHR.rounded()), maxHr: s.peakHR, strain: s.strain,
                distanceM: nil, zonesJSON: zjson, notes: nil)
        }
    }
}

/// Pure helpers so a WHOOP import does not re-score nights the CSV already filled,
/// while nights the import did not cover (new strap data) still get scored.
enum IntelligenceSkip {
    /// The newest nights are always rescored. A pass can run before the strap has
    /// finished offloading, scoring last night from partial data; without this the
    /// day would count as "done" forever and never converge once the rest arrives.
    static let alwaysRescoreDays = 2

    static func scoredDays(in days: [DailyMetric]) -> Set<String> {
        Set(days.compactMap { $0.recovery != nil ? $0.day : nil })
    }

    static func shouldSkip(utcDay: String, localDay: String, scored: Set<String>,
                           dayOffset: Int) -> Bool {
        guard dayOffset >= alwaysRescoreDays else { return false }
        return scored.contains(utcDay) || scored.contains(localDay)
    }
}
