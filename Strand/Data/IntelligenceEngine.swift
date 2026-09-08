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
    func analyzeRecent(maxDays: Int = PhoneBudget.intelligenceDays) async {
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
        let now = Int(Date().timeIntervalSince1970)
        var out: [Computed] = []
        var dailies: [DailyMetric] = []
        var cachedSleep: [CachedSleepSession] = []
        let sampleLimit = PhoneBudget.intelligenceSampleLimit

        for offset in 0..<maxDays {
            let dayStart = now - offset * 86_400
            let day = AnalyticsEngine.dayString(dayStart)
            // Read a generous window around the night that ends on `day`; the stager finds the span.
            let from = dayStart - 30 * 3_600
            let to = dayStart + 12 * 3_600

            let hr = (try? await store.hrSamples(deviceId: deviceId, from: from, to: to, limit: sampleLimit)) ?? []
            guard hr.count >= 200 else { continue }   // need real raw data, not a stray sample
            let rr = (try? await store.rrIntervals(deviceId: deviceId, from: from, to: to, limit: sampleLimit)) ?? []
            let resp = (try? await store.respSamples(deviceId: deviceId, from: from, to: to, limit: sampleLimit)) ?? []
            let grav = (try? await store.gravitySamples(deviceId: deviceId, from: from, to: to, limit: sampleLimit)) ?? []

            let res = await Self.analyzeDayOffMain(day: day, hr: hr, rr: rr, resp: resp, gravity: grav,
                                                   profile: up, baselines: baselines, maxHROverride: maxHR)
            out.append(Computed(day: day, recovery: res.recovery, strain: res.strain,
                                sleepMin: res.daily.totalSleepMin, hrv: res.daily.avgHrv,
                                rhr: res.daily.restingHr))
            dailies.append(res.daily)
            cachedSleep.append(contentsOf: res.cachedSleep)
            await Task.yield()
        }

        // Persist the computed scores under a dedicated "-noop" source so the WHOLE dashboard
        // (Today / Recovery / Strain / Sleep / Trends), not just this screen, reads them. The
        // Repository merges these UNDER any imported "my-whoop" rows, so a real WHOOP import
        // always wins; this only fills the days the strap collected but no import covered.
        let computedId = deviceId + "-noop"
        if !dailies.isEmpty { _ = try? await store.upsertDailyMetrics(dailies, deviceId: computedId) }
        if !cachedSleep.isEmpty { _ = try? await store.upsertSleepSessions(cachedSleep, deviceId: computedId) }

        results = out
        note = out.isEmpty
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
        maxHROverride: Double?
    ) async -> AnalyticsEngine.DayResult {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                let result = AnalyticsEngine.analyzeDay(
                    day: day, hr: hr, rr: rr, resp: resp, gravity: gravity,
                    profile: profile, baselines: baselines, maxHROverride: maxHROverride)
                cont.resume(returning: result)
            }
        }
    }
}
