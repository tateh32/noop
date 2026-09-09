import Foundation
import Combine
import WhoopProtocol
import WhoopStore
import StrandAnalytics

#if os(iOS)
import CoreLocation
import CoreMotion
#endif

/// In-progress live workout. Owned by `AppModel` so switching Today ↔ Live does not kill it.
@MainActor
final class LiveSessionRecorder: ObservableObject {
    @Published private(set) var running = false
    @Published var sport: String = WorkoutSport.running.rawValue
    @Published private(set) var elapsedS: Int = 0
    @Published private(set) var distanceM: Double = 0
    @Published private(set) var steps: Int = 0
    @Published private(set) var lastBpm: Int?
    @Published private(set) var avgHr: Int?
    @Published private(set) var maxHr: Int?
    @Published private(set) var gpsNote: String = ""
    @Published var error: String?

    /// Fired when a session stops (saved or discarded) so the owner can shut the
    /// heavy realtime BLE stream back down.
    var onSessionEnded: (() -> Void)?

    /// 8 hours at ~1 Hz. Bounds both memory and the calorie series.
    static let maxHrTicks = 8 * 3600
    /// Snapshot cadence. Only aggregates are written, so this is cheap.
    static let persistIntervalS: TimeInterval = 15

    private var startedAt: Date?
    private var hrTicks: [Int] = []
    private var hrSum = 0
    private var lastLat: Double?
    private var lastLon: Double?
    private var tickTimer: DispatchSourceTimer?
    private var lastPersistAt: TimeInterval = 0
    private var lastHrTickAt: TimeInterval = 0
    private var hrProvider: (() -> Int?)?
    private var kcalProfile: UserProfile?
    private var hrMax: Double?

    #if os(iOS)
    private let gps = SessionGPS()
    private let pedometer = CMPedometer()
    #endif

    var usesGPS: Bool { WorkoutSport(rawValue: sport)?.usesPhoneGPS ?? false }
    var usesSteps: Bool { WorkoutSport(rawValue: sport)?.usesPedometer ?? false }

    var elapsedLabel: String {
        let h = elapsedS / 3600
        let m = (elapsedS % 3600) / 60
        let s = elapsedS % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    var distanceLabel: String {
        guard distanceM > 0 else { return "—" }
        if distanceM >= 1000 { return String(format: "%.2f km", distanceM / 1000) }
        return "\(Int(distanceM.rounded())) m"
    }

    var paceLabel: String {
        guard distanceM >= 50, elapsedS > 0 else { return "—" }
        let minPerKm = (Double(elapsedS) / 60.0) / (distanceM / 1000.0)
        guard minPerKm.isFinite, minPerKm > 0, minPerKm < 99 else { return "—" }
        let whole = Int(minPerKm)
        let frac = Int((minPerKm - Double(whole)) * 60)
        return String(format: "%d:%02d /km", whole, frac)
    }

    func start(sport: String, hr: @escaping () -> Int?, profile: ProfileStore) {
        guard !running else { return }
        self.sport = sport
        hrProvider = hr
        kcalProfile = UserProfile(weightKg: profile.weightKg, heightCm: profile.heightCm,
                                  age: Double(profile.age), sex: profile.sex)
        hrMax = Double(profile.hrMax)
        startedAt = Date()
        elapsedS = 0
        distanceM = 0
        steps = 0
        lastBpm = nil
        avgHr = nil
        maxHr = nil
        hrTicks = []
        hrSum = 0
        lastLat = nil
        lastLon = nil
        lastHrTickAt = 0
        lastPersistAt = 0
        error = nil
        #if os(iOS)
        gpsNote = usesGPS ? "GPS seeking…" : "GPS off for this sport"
        #else
        gpsNote = usesGPS ? "GPS is iPhone-only" : "GPS off for this sport"
        #endif
        running = true
        startTicker()
        startSensors()
        persist()
    }

    /// Resume a session after jetsam / process death. Returns true if one was running.
    @discardableResult
    func restoreIfNeeded(hr: @escaping () -> Int?, profile: ProfileStore) -> Bool {
        // Never clear the snapshot while a session is live — that would destroy the
        // crash-recovery record for the workout currently running.
        guard !running else { return false }
        guard let snap = LiveSessionSnapshot.load(), snap.isFresh else {
            LiveSessionSnapshot.clear()
            return false
        }
        sport = snap.sport
        hrProvider = hr
        kcalProfile = UserProfile(weightKg: profile.weightKg, heightCm: profile.heightCm,
                                  age: Double(profile.age), sex: profile.sex)
        hrMax = Double(profile.hrMax)
        startedAt = Date(timeIntervalSince1970: snap.startedAt)
        distanceM = snap.distanceM
        steps = snap.steps
        // The snapshot stores HR aggregates, not every beat. Rebuild a flat series
        // at the mean so calories stay in the right ballpark after a resume.
        if snap.hrCount > 0 {
            let mean = Int((Double(snap.hrSum) / Double(snap.hrCount)).rounded())
            hrTicks = Array(repeating: mean, count: min(snap.hrCount, Self.maxHrTicks))
            hrSum = hrTicks.reduce(0, +)
            avgHr = mean
            lastBpm = mean
        } else {
            hrTicks = []
            hrSum = 0
        }
        maxHr = snap.hrMax
        error = nil
        #if os(iOS)
        gpsNote = usesGPS ? "GPS resuming…" : "GPS off for this sport"
        #else
        gpsNote = usesGPS ? "GPS is iPhone-only" : "GPS off for this sport"
        #endif
        running = true
        refreshElapsed()
        startTicker()
        startSensors()
        return true
    }

    /// Attach GPS and the pedometer for the current sport. Idempotent enough to
    /// call on start, on resume, and when a failed save keeps the session alive.
    private func startSensors() {
        #if os(iOS)
        if usesGPS {
            gps.onFix = { [weak self] lat, lon, acc in self?.ingestFix(lat: lat, lon: lon, accuracy: acc) }
            gps.onDenied = { [weak self] in
                self?.gpsNote = "Location off — distance unavailable. Enable it in Settings → NOOP."
            }
            gps.begin()
        }
        if usesSteps, CMPedometer.isStepCountingAvailable(), let start = startedAt {
            pedometer.stopUpdates()   // no-op if idle; avoids stacking handlers on resume
            pedometer.startUpdates(from: start) { [weak self] data, _ in
                let n = data?.numberOfSteps.intValue ?? 0
                Task { @MainActor in self?.steps = n }
            }
        }
        #endif
    }

    /// Called from AppModel on every strap HR sample so a backgrounded workout
    /// still records beats when the 1 Hz timer is frozen. Aggregates are kept
    /// running (O(1)) — a `reduce`/`max` over the whole series on every beat cost
    /// ~29k operations per second by the end of a long session.
    func noteHR(_ bpm: Int?) {
        guard running else { return }
        refreshElapsed()
        guard let bpm, (30...220).contains(bpm) else { return }
        lastBpm = bpm
        let now = Date().timeIntervalSince1970
        // BLE notify + 1 Hz ticker both call this; keep ~1 sample/s for calories.
        guard now - lastHrTickAt >= 0.8 else { return }
        lastHrTickAt = now
        hrTicks.append(bpm)
        hrSum += bpm
        if hrTicks.count > Self.maxHrTicks {
            let drop = hrTicks.count - Self.maxHrTicks
            hrSum -= hrTicks.prefix(drop).reduce(0, +)
            hrTicks.removeFirst(drop)
        }
        avgHr = Int((Double(hrSum) / Double(hrTicks.count)).rounded())
        maxHr = max(maxHr ?? bpm, bpm)
        persistThrottled()
    }

    func discard() {
        tearDownSensors()
        LiveSessionSnapshot.clear()
        running = false
        hrProvider = nil
        gpsNote = ""
        onSessionEnded?()
    }

    func save(into repo: Repository) async -> Bool {
        guard running, let start = startedAt else { return false }
        tearDownSensors()
        let end = Date()
        let duration = max(1, end.timeIntervalSince(start))
        let meanHR: Int? = hrTicks.isEmpty ? nil : Int((Double(hrSum) / Double(hrTicks.count)).rounded())
        let peakHR = maxHr
        var kcal: Double? = nil
        if let profile = kcalProfile, !hrTicks.isEmpty {
            let samples: [HRSample] = hrTicks.enumerated().map { i, bpm in
                HRSample(ts: Int(start.timeIntervalSince1970) + i, bpm: bpm)
            }
            let est = Calories.estimateBoutCalories(samples, profile: profile, hrmax: hrMax, restingHR: 60)
            if est.0 > 0 { kcal = est.0 }
        }
        var noteBits: [String] = ["Live session"]
        if usesGPS {
            noteBits.append(distanceM > 0 ? "phone GPS" : "GPS no fix")
        }
        if steps > 0 { noteBits.append("\(steps) steps") }
        let dist = distanceM > 0 ? distanceM : nil
        let row = WorkoutRow(
            startTs: Int(start.timeIntervalSince1970),
            endTs: Int(end.timeIntervalSince1970),
            sport: sport, source: "logged",
            durationS: duration, energyKcal: kcal, avgHr: meanHR, maxHr: peakHR,
            strain: Double?.none, distanceM: dist, zonesJSON: String?.none,
            notes: noteBits.joined(separator: " · "))
        // Do not tear down until the row is durable. Clearing first meant a failed
        // write (store busy, disk pressure) lost the workout with no way to retry,
        // even though the UI offered "Stop and save again".
        let saved = await repo.logWorkout(row)
        guard saved else {
            // Keep the session fully alive for the retry — the ticker alone would
            // leave distance and steps frozen while the clock kept moving.
            startTicker()
            startSensors()
            return false
        }
        running = false
        hrProvider = nil
        gpsNote = ""
        LiveSessionSnapshot.clear()
        onSessionEnded?()
        return true
    }

    private func startTicker() {
        tickTimer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now(), repeating: 1.0)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        tickTimer = t
    }

    private func tick() {
        guard running else { return }
        refreshElapsed()
        noteHR(hrProvider?())
    }

    private func refreshElapsed() {
        guard running, let start = startedAt else { return }
        elapsedS = max(0, Int(Date().timeIntervalSince(start)))
    }

    func persist() {
        guard running, let start = startedAt else { return }
        LiveSessionSnapshot(sport: sport, startedAt: start.timeIntervalSince1970,
                            distanceM: distanceM, steps: steps,
                            hrSum: hrSum, hrCount: hrTicks.count, hrMax: maxHr).save()
        lastPersistAt = Date().timeIntervalSince1970
    }

    private func persistThrottled() {
        let now = Date().timeIntervalSince1970
        guard now - lastPersistAt >= Self.persistIntervalS else { return }
        persist()
    }

    private func ingestFix(lat: Double, lon: Double, accuracy: Double) {
        guard running, usesGPS else { return }
        refreshElapsed()
        gpsNote = String(format: "GPS ±%.0f m", accuracy)
        if let pLat = lastLat, let pLon = lastLon {
            let delta = GeoDistance.meters(fromLat: pLat, lon: pLon, toLat: lat, lon: lon)
            if GeoDistance.shouldAccumulate(deltaM: delta, accuracyM: accuracy) {
                distanceM += delta
            }
        }
        if GeoDistance.usableAccuracy(accuracy) {
            lastLat = lat
            lastLon = lon
        }
    }

    private func tearDownSensors() {
        tickTimer?.cancel()
        tickTimer = nil
        #if os(iOS)
        gps.stop()
        if CMPedometer.isStepCountingAvailable() { pedometer.stopUpdates() }
        #endif
    }
}

/// On-disk in-progress workout. Survives iOS jetsam so "it just stopped" can resume.
///
/// Stores HR *aggregates*, not the whole beat series: this is rewritten every 15
/// seconds while a workout runs, and encoding a series that grows to ~29k entries
/// (~115 KB of JSON) on the main thread was a needless hitch every 15 s.
struct LiveSessionSnapshot: Codable, Equatable {
    var sport: String
    var startedAt: TimeInterval
    var distanceM: Double
    var steps: Int
    var hrSum: Int
    var hrCount: Int
    var hrMax: Int?

    /// v2 stores HR aggregates instead of every beat. The key is versioned so a
    /// v1 blob is ignored rather than failing to decode.
    static let defaultsKey = "noop.liveSession.v2"
    static let maxAge: TimeInterval = 12 * 3600

    var isFresh: Bool {
        let age = Date().timeIntervalSince1970 - startedAt
        return age >= 0 && age <= Self.maxAge
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    static func load() -> LiveSessionSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(LiveSessionSnapshot.self, from: data)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    static func decode(_ data: Data) -> LiveSessionSnapshot? {
        try? JSONDecoder().decode(LiveSessionSnapshot.self, from: data)
    }
}

#if os(iOS)
/// CoreLocation wrapper. Delegate is a plain NSObject (not MainActor).
private final class SessionGPS: NSObject, CLLocationManagerDelegate {
    var onFix: ((Double, Double, Double) -> Void)?
    var onDenied: (() -> Void)?
    private let manager = CLLocationManager()
    private var started = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
    }

    func begin() {
        started = true
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            startUpdates()
        default:
            onDenied?()
        }
    }

    func stop() {
        started = false
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
    }

    /// "While Using the App" is enough to keep a locked-screen workout tracking:
    /// the `location` background mode plus the blue status indicator is the
    /// standard fitness pattern, so we do not nag for Always. Setting
    /// `allowsBackgroundLocationUpdates` without authorization throws, hence the guard.
    private func startUpdates() {
        let status = manager.authorizationStatus
        guard status == .authorizedAlways || status == .authorizedWhenInUse else {
            onDenied?()
            return
        }
        manager.allowsBackgroundLocationUpdates = true
        manager.startUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard started else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            startUpdates()
        case .notDetermined:
            break
        default:
            onDenied?()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        let lat = loc.coordinate.latitude
        let lon = loc.coordinate.longitude
        let acc = loc.horizontalAccuracy
        DispatchQueue.main.async { [weak self] in
            self?.onFix?(lat, lon, acc)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Transient GPS misses are normal outdoors; do not treat them as a permission denial.
    }
}
#endif
