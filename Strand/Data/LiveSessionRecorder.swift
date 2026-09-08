import Foundation
import Combine
import WhoopProtocol
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
        error = nil
        #if os(iOS)
        gpsNote = usesGPS ? "GPS seeking…" : "GPS off for this sport"
        #else
        gpsNote = usesGPS ? "GPS is iPhone-only" : "GPS off for this sport"
        #endif
        running = true

        timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            self?.tick()
        }

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

    func discard() {
        tearDownSensors()
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
            strain: nil, distanceM: dist, zonesJSON: nil,
            notes: noteBits.joined(separator: " · "))
        running = false
        hrProvider = nil
        gpsNote = ""
        return await repo.logWorkout(row)
    }

    private func tick() {
        guard running, let start = startedAt else { return }
        elapsedS = max(0, Int(Date().timeIntervalSince(start)))
        if let bpm = hrProvider?(), (30...220).contains(bpm) {
            lastBpm = bpm
            hrTicks.append(bpm)
            avgHr = Int((Double(hrTicks.reduce(0, +)) / Double(hrTicks.count)).rounded())
            maxHr = hrTicks.max()
        }
    }

    private func ingestFix(lat: Double, lon: Double, accuracy: Double) {
        guard running, usesGPS else { return }
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
        #if os(iOS)
        gps.stop()
        if CMPedometer.isStepCountingAvailable() { pedometer.stopUpdates() }
        #endif
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

    private func startUpdates() {
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
