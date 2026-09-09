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

    private var startedAt: Date?
    private var hrTicks: [Int] = []
    private var lastLat: Double?
    private var lastLon: Double?
    private var timer: AnyCancellable?
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
        persist()

        #if os(iOS)
        if usesGPS {
            gps.onFix = { [weak self] lat, lon, acc in self?.ingestFix(lat: lat, lon: lon, accuracy: acc) }
            gps.onDenied = { [weak self] in
                self?.gpsNote = "Location off — distance unavailable. Enable it in Settings → NOOP."
            }
            gps.begin()
        }
        if usesSteps, CMPedometer.isStepCountingAvailable(), let start = startedAt {
            pedometer.startUpdates(from: start) { [weak self] data, _ in
                let n = data?.numberOfSteps.intValue ?? 0
                Task { @MainActor in self?.steps = n }
            }
        }
        #endif
    }

    /// Resume a session after jetsam / process death. Returns true if one was running.
    @discardableResult
    func restoreIfNeeded(hr: @escaping () -> Int?, profile: ProfileStore) -> Bool {
        guard !running, let snap = LiveSessionSnapshot.load(), snap.isFresh else {
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
        hrTicks = snap.hrTicks
        lastBpm = hrTicks.last
        avgHr = hrTicks.isEmpty ? nil : Int((Double(hrTicks.reduce(0, +)) / Double(hrTicks.count)).rounded())
        maxHr = hrTicks.max()
        error = nil
        #if os(iOS)
        gpsNote = usesGPS ? "GPS resuming…" : "GPS off for this sport"
        #else
        gpsNote = usesGPS ? "GPS is iPhone-only" : "GPS off for this sport"
        #endif
        running = true
        refreshElapsed()
        startTicker()
        #if os(iOS)
        if usesGPS {
            gps.onFix = { [weak self] lat, lon, acc in self?.ingestFix(lat: lat, lon: lon, accuracy: acc) }
            gps.onDenied = { [weak self] in
                self?.gpsNote = "Location off — distance unavailable. Enable it in Settings → NOOP."
            }
            gps.begin()
        }
        if usesSteps, CMPedometer.isStepCountingAvailable(), let start = startedAt {
            pedometer.startUpdates(from: start) { [weak self] data, _ in
                let n = data?.numberOfSteps.intValue ?? 0
                Task { @MainActor in self?.steps = n }
            }
        }
        #endif
        return true
    }

    /// Called from AppModel on every strap HR sample so a backgrounded workout
    /// still records beats when the 1 Hz RunLoop timer is frozen.
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
        if hrTicks.count > 8 * 3600 { hrTicks.removeFirst(hrTicks.count - 8 * 3600) }
        avgHr = Int((Double(hrTicks.reduce(0, +)) / Double(hrTicks.count)).rounded())
        maxHr = hrTicks.max()
        persistThrottled()
    }

    func discard() {
        tearDownSensors()
        LiveSessionSnapshot.clear()
        running = false
        hrProvider = nil
        gpsNote = ""
    }

    func save(into repo: Repository) async -> Bool {
        guard running, let start = startedAt else { return false }
        tearDownSensors()
        let end = Date()
        let duration = max(1, end.timeIntervalSince(start))
        let meanHR: Int? = hrTicks.isEmpty ? nil : Int((Double(hrTicks.reduce(0, +)) / Double(hrTicks.count)).rounded())
        let peakHR = hrTicks.max()
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
        running = false
        hrProvider = nil
        gpsNote = ""
        LiveSessionSnapshot.clear()
        return await repo.logWorkout(row)
    }

    private func startTicker() {
        timer?.cancel()
        timer = nil
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
                            distanceM: distanceM, steps: steps, hrTicks: hrTicks).save()
        lastPersistAt = Date().timeIntervalSince1970
    }

    private func persistThrottled() {
        let now = Date().timeIntervalSince1970
        guard now - lastPersistAt >= 15 else { return }
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
        timer?.cancel()
        timer = nil
        tickTimer?.cancel()
        tickTimer = nil
        #if os(iOS)
        gps.stop()
        if CMPedometer.isStepCountingAvailable() { pedometer.stopUpdates() }
        #endif
    }
}

/// On-disk in-progress workout. Survives iOS jetsam so "it just stopped" can resume.
struct LiveSessionSnapshot: Codable, Equatable {
    var sport: String
    var startedAt: TimeInterval
    var distanceM: Double
    var steps: Int
    var hrTicks: [Int]

    static let defaultsKey = "noop.liveSession.v1"
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
    private var askedAlways = false

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
        case .authorizedAlways:
            startUpdates()
        case .authorizedWhenInUse:
            startUpdates()
            requestAlwaysOnce()
        default:
            onDenied?()
        }
    }

    func stop() {
        started = false
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
    }

    private func startUpdates() {
        manager.allowsBackgroundLocationUpdates = true
        manager.startUpdatingLocation()
    }

    private func requestAlwaysOnce() {
        guard !askedAlways else { return }
        askedAlways = true
        manager.requestAlwaysAuthorization()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard started else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways:
            startUpdates()
        case .authorizedWhenInUse:
            startUpdates()
            requestAlwaysOnce()
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
