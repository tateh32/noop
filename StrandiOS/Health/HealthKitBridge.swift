import Foundation
import Combine
import HealthKit
import StrandImport
import WhoopStore
import WhoopProtocol
import StrandAnalytics

/// Two-way Apple Health on iPhone. Opt-in, on-device. Reads live sleep and
/// workouts (and the `AppleHealthImporter.relevantTypes` set) into the same
/// store path as `export.zip`. Writes NOOP sleep, workouts, HR, HRV, RHR,
/// SpO₂ and recovery (recovery rides as metadata — Health has no recovery type).
@MainActor
final class HealthKitBridge: ObservableObject {
    static let enabledKey = "noop.healthKitSync"
    private static let hrWatermarkKey = "noop.hk.hrTs"
    private static let sleepWatermarkKey = "noop.hk.sleepEnd"
    private static let workoutWatermarkKey = "noop.hk.workoutEnd"
    private static let dailyWatermarkKey = "noop.hk.dailyDay"

    @Published var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
            if enabled { Task { await start() } }
        }
    }
    @Published var status: String?
    @Published var lastError: String?

    private let store = HKHealthStore()
    private var lastPushAt: Date = .distantPast
    private var lastIngestAt: Date = .distantPast
    private var started = false
    private var observers: [HKObserverQuery] = []
    /// Wired by AppModel so an HK observer can pull without holding the store.
    var onExternalChange: (() -> Void)?

    init() {
        enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func start() async {
        guard enabled, isAvailable else { return }
        let ok = await requestAuth()
        guard ok else {
            status = "Health access not granted."
            return
        }
        started = true
        status = "Apple Health on — on this iPhone only."
        enableBackgroundDelivery()
        startObservers()
    }

    func ingest(into repo: Repository) async {
        guard enabled, isAvailable, started || UserDefaults.standard.bool(forKey: Self.enabledKey) else { return }
        if !started {
            let ok = await requestAuth()
            guard ok else { return }
            started = true
            enableBackgroundDelivery()
            startObservers()
        }
        if Date().timeIntervalSince(lastIngestAt) < 45 { return }
        lastIngestAt = Date()
        do {
            let result = try await pullRecent()
            guard let handle = await repo.storeHandle() else { return }
            try await AppleHealthImport.persist(result, into: handle, deviceId: "apple-health")
            await repo.refresh()
            let n = result.summary.recordCount
            if n > 0 { status = "Apple Health: read \(n) records." }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func pushNOOP(days: [DailyMetric], sleeps: [CachedSleepSession],
                    workouts: [WorkoutRow], hr: [HRSample]) async {
        guard enabled, isAvailable else { return }
        if Date().timeIntervalSince(lastPushAt) < 120 { return }
        lastPushAt = Date()
        let d = UserDefaults.standard
        let sleepCut = d.integer(forKey: Self.sleepWatermarkKey)
        let workoutCut = d.integer(forKey: Self.workoutWatermarkKey)
        let hrCut = d.integer(forKey: Self.hrWatermarkKey)
        let dayCut = d.string(forKey: Self.dailyWatermarkKey) ?? ""
        let newSleeps = HealthKitMapper.sleepsAfter(sleeps, endTs: sleepCut)
        let newWorkouts = HealthKitMapper.workoutsAfter(workouts, endTs: workoutCut)
        let newHR = hr.filter { $0.ts > hrCut }
        let newDays = HealthKitMapper.daysAfter(days, day: dayCut)
        var samples: [HKSample] = []
        samples.append(contentsOf: Self.sleepSamples(newSleeps))
        samples.append(contentsOf: Self.workoutSamples(newWorkouts))
        samples.append(contentsOf: Self.quantitySamples(days: newDays, hr: newHR))
        guard !samples.isEmpty else { return }
        do {
            try await save(samples)
            if let t = newSleeps.map(\.endTs).max() {
                d.set(max(sleepCut, t), forKey: Self.sleepWatermarkKey)
            }
            if let t = newWorkouts.map(\.endTs).max() {
                d.set(max(workoutCut, t), forKey: Self.workoutWatermarkKey)
            }
            if let t = newHR.map(\.ts).max() {
                d.set(max(hrCut, t), forKey: Self.hrWatermarkKey)
            }
            if let day = newDays.map(\.day).max() {
                d.set(day, forKey: Self.dailyWatermarkKey)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func writeWorkout(_ row: WorkoutRow) async {
        guard enabled, isAvailable else { return }
        let cut = UserDefaults.standard.integer(forKey: Self.workoutWatermarkKey)
        guard row.endTs > cut else { return }
        let samples = Self.workoutSamples([row])
        do {
            try await save(samples)
            UserDefaults.standard.set(max(cut, row.endTs), forKey: Self.workoutWatermarkKey)
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Auth

    private var shareTypes: Set<HKSampleType> {
        var s: Set<HKSampleType> = []
        if let t = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { s.insert(t) }
        s.insert(HKObjectType.workoutType())
        if let t = HKObjectType.quantityType(forIdentifier: .heartRate) { s.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) { s.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .restingHeartRate) { s.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .oxygenSaturation) { s.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .bodyTemperature) { s.insert(t) }
        return s
    }

    private var readTypes: Set<HKObjectType> {
        var s: Set<HKObjectType> = shareTypes
        for id in [
            HKQuantityTypeIdentifier.stepCount,
            .activeEnergyBurned,
            .basalEnergyBurned,
            .vo2Max,
            .bodyMass,
            .respiratoryRate,
            .walkingHeartRateAverage,
        ] {
            if let t = HKObjectType.quantityType(forIdentifier: id) { s.insert(t) }
        }
        return s
    }

    private func requestAuth() async -> Bool {
        await withCheckedContinuation { cont in
            store.requestAuthorization(toShare: shareTypes, read: readTypes) { ok, _ in
                cont.resume(returning: ok)
            }
        }
    }

    private func enableBackgroundDelivery() {
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            store.enableBackgroundDelivery(for: sleep, frequency: .hourly) { _, _ in }
        }
        store.enableBackgroundDelivery(for: HKObjectType.workoutType(), frequency: .hourly) { _, _ in }
    }

    /// Background delivery only wakes the app when an observer query is registered.
    private func startObservers() {
        guard observers.isEmpty else { return }
        var types: [HKSampleType] = [HKObjectType.workoutType()]
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.append(sleep)
        }
        for t in types {
            let q = HKObserverQuery(sampleType: t, predicate: nil) { [weak self] _, completion, _ in
                completion()
                Task { @MainActor in self?.onExternalChange?() }
            }
            observers.append(q)
            store.execute(q)
        }
    }

    static func sportName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: return "Running"
        case .walking: return "Walking"
        case .cycling: return "Cycling"
        case .traditionalStrengthTraining: return "Strength"
        case .highIntensityIntervalTraining: return "HIIT"
        case .yoga: return "Yoga"
        case .swimming: return "Swimming"
        case .hiking: return "Hiking"
        default: return "Workout"
        }
    }

    // MARK: Read

    private func pullRecent() async throws -> AppleHealthImportResult {
        let end = Date()
        let start = end.addingTimeInterval(-14 * 86_400)
        var samples: [HealthSample] = []
        var intervals: [SleepStageInterval] = []
        var workouts: [HealthWorkout] = []

        if let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            let hk = try await queryCategory(sleepType, start: start, end: end)
            for s in hk where !Self.isNOOPSource(s) {
                let stage = HealthKitMapper.sleepStage(fromCategoryValue: s.value)
                let tz = TimeZone.current.secondsFromGMT() / 60
                intervals.append(SleepStageInterval(stage: stage, start: s.startDate, end: s.endDate,
                                                    tzOffsetMin: tz, sourceName: s.sourceRevision.source.name))
                samples.append(HealthSample(type: "SleepAnalysis", value: nil,
                                            valueString: String(s.value), unit: nil,
                                            start: s.startDate, end: s.endDate,
                                            tzOffsetMin: tz,
                                            sourceName: s.sourceRevision.source.name))
            }
        }

        let hkWorkouts = try await queryWorkouts(start: start, end: end)
        let tz = TimeZone.current.secondsFromGMT() / 60
        for w in hkWorkouts where !Self.isNOOPSource(w) {
            workouts.append(HealthWorkout(
                activityType: Self.sportName(w.workoutActivityType),
                durationS: w.duration,
                distanceM: w.totalDistance?.doubleValue(for: .meter()),
                energyKcal: w.totalEnergyBurned?.doubleValue(for: .kilocalorie()),
                start: w.startDate, end: w.endDate, tzOffsetMin: tz,
                sourceName: w.sourceRevision.source.name))
        }

        let qty: [(HKQuantityTypeIdentifier, String, HKUnit, Double)] = [
            (.heartRate, "HeartRate", HKUnit.count().unitDivided(by: .minute()), 1),
            (.restingHeartRate, "RestingHeartRate", HKUnit.count().unitDivided(by: .minute()), 1),
            (.heartRateVariabilitySDNN, "HeartRateVariabilitySDNN", HKUnit.secondUnit(with: .milli), 1),
            (.oxygenSaturation, "OxygenSaturation", .percent(), 100),
            (.respiratoryRate, "RespiratoryRate", HKUnit.count().unitDivided(by: .minute()), 1),
            (.stepCount, "StepCount", .count(), 1),
            (.activeEnergyBurned, "ActiveEnergyBurned", .kilocalorie(), 1),
            (.bodyMass, "BodyMass", .gramUnit(with: .kilo), 1),
        ]
        for (id, type, unit, scale) in qty {
            guard let qt = HKObjectType.quantityType(forIdentifier: id) else { continue }
            let rows = try await queryQuantity(qt, start: start, end: end)
            for s in rows where !Self.isNOOPSource(s) {
                var v = s.quantity.doubleValue(for: unit) * scale
                if type == "OxygenSaturation", v <= 1.5 { v *= 100 } // HealthKit is 0–1
                samples.append(HealthSample(type: type, value: v, valueString: String(v),
                                              unit: unit.unitString, start: s.startDate, end: s.endDate,
                                              tzOffsetMin: tz, sourceName: s.sourceRevision.source.name))
            }
        }

        let summary = ImportSummary(sourceKind: .appleHealth, recordCount: samples.count + workouts.count,
                                     earliest: samples.map(\.start).min() ?? workouts.map(\.start).min(),
                                     latest: samples.map(\.end).max() ?? workouts.map(\.end).max(),
                                     countsByCategory: [:])
        return AppleHealthImportResult(samples: samples, workouts: workouts,
                                       sleepIntervals: intervals, summary: summary)
    }

    private func queryCategory(_ type: HKCategoryType, start: Date, end: Date) async throws -> [HKCategorySample] {
        try await withCheckedThrowingContinuation { cont in
            let pred = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let q = HKSampleQuery(sampleType: type, predicate: pred, limit: HKObjectQueryNoLimit,
                                    sortDescriptors: nil) { _, samples, err in
                if let err { cont.resume(throwing: err); return }
                cont.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            store.execute(q)
        }
    }

    private func queryQuantity(_ type: HKQuantityType, start: Date, end: Date) async throws -> [HKQuantitySample] {
        try await withCheckedThrowingContinuation { cont in
            let pred = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let q = HKSampleQuery(sampleType: type, predicate: pred, limit: 20_000,
                                    sortDescriptors: nil) { _, samples, err in
                if let err { cont.resume(throwing: err); return }
                cont.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            store.execute(q)
        }
    }

    private func queryWorkouts(start: Date, end: Date) async throws -> [HKWorkout] {
        try await withCheckedThrowingContinuation { cont in
            let pred = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let q = HKSampleQuery(sampleType: .workoutType(), predicate: pred, limit: 500,
                                    sortDescriptors: nil) { _, samples, err in
                if let err { cont.resume(throwing: err); return }
                cont.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(q)
        }
    }

    // MARK: Write

    private func save(_ samples: [HKSample]) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            store.save(samples) { _, err in
                if let err { cont.resume(throwing: err) }
                else { cont.resume() }
            }
        }
    }

    static func sleepSamples(_ sleeps: [CachedSleepSession]) -> [HKSample] {
        guard let cat = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        var out: [HKSample] = []
        for s in sleeps {
            let segs = HealthKitMapper.writeSegments(from: s.stagesJSON)
            let meta: [String: Any] = s.efficiency.map { ["NOOPEfficiency": $0] } ?? [:]
            if segs.isEmpty {
                let start = Date(timeIntervalSince1970: TimeInterval(s.startTs))
                let end = Date(timeIntervalSince1970: TimeInterval(s.endTs))
                out.append(HKCategorySample(type: cat, value: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                                              start: start, end: end, metadata: meta))
                continue
            }
            for (i, seg) in segs.enumerated() {
                var m = meta
                if i == 0, let rec = meta["NOOPRecovery"] { m["NOOPRecovery"] = rec }
                let v = HealthKitMapper.categoryValue(stageLabel: seg.label)
                out.append(HKCategorySample(type: cat, value: v,
                                            start: Date(timeIntervalSince1970: TimeInterval(seg.start)),
                                            end: Date(timeIntervalSince1970: TimeInterval(seg.end)),
                                            metadata: m.isEmpty ? nil : m))
            }
        }
        return out
    }

    static func workoutSamples(_ rows: [WorkoutRow]) -> [HKSample] {
        rows.compactMap { r -> HKWorkout? in
            let start = Date(timeIntervalSince1970: TimeInterval(r.startTs))
            let end = Date(timeIntervalSince1970: TimeInterval(r.endTs))
            let dur = r.durationS ?? end.timeIntervalSince(start)
            let energy = r.energyKcal.map { HKQuantity(unit: .kilocalorie(), doubleValue: $0) }
            let dist = r.distanceM.map { HKQuantity(unit: .meter(), doubleValue: $0) }
            return HKWorkout(activityType: Self.activityType(r.sport),
                              start: start, end: end, duration: dur,
                              totalEnergyBurned: energy, totalDistance: dist,
                              metadata: ["NOOPSource": r.source])
        }
    }

    static func quantitySamples(days: [DailyMetric], hr: [HRSample]) -> [HKSample] {
        var out: [HKSample] = []
        let bpmUnit = HKUnit.count().unitDivided(by: .minute())
        if let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) {
            // Downsample to ~1/min so Health is not flooded with 1 Hz strap beats.
            var last = 0
            for s in hr {
                if s.ts - last < 50 { continue }
                last = s.ts
                let t = Date(timeIntervalSince1970: TimeInterval(s.ts))
                out.append(HKQuantitySample(type: hrType,
                                              quantity: HKQuantity(unit: bpmUnit, doubleValue: Double(s.bpm)),
                                              start: t, end: t))
            }
        }
        if let rhrType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate),
           let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN),
           let spo2Type = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation) {
            for d in days.suffix(7) {
                guard let date = Self.noon(d.day) else { continue }
                if let rhr = d.restingHr {
                    out.append(HKQuantitySample(type: rhrType,
                                                  quantity: HKQuantity(unit: bpmUnit, doubleValue: Double(rhr)),
                                                  start: date, end: date))
                }
                if let hrv = d.avgHrv {
                    out.append(HKQuantitySample(type: hrvType,
                                              quantity: HKQuantity(unit: HKUnit.secondUnit(with: .milli), doubleValue: hrv),
                                              start: date, end: date))
                }
                if let spo2 = d.spo2Pct {
                    out.append(HKQuantitySample(type: spo2Type,
                                              quantity: HKQuantity(unit: .percent(), doubleValue: spo2 / 100.0),
                                              start: date, end: date))
                }
            }
        }
        // Recovery has no HK quantity type. Attach it to last night's sleep via a
        // 1-second in-bed sample carrying metadata Health stores on-device.
        if let recType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis),
           let last = days.last(where: { $0.recovery != nil }),
           let date = Self.noon(last.day), let rec = last.recovery {
            let meta = HealthKitMapper.recoveryMetadata(score: rec)
            out.append(HKCategorySample(type: recType,
                                          value: HKCategoryValueSleepAnalysis.inBed.rawValue,
                                          start: date, end: date.addingTimeInterval(1),
                                          metadata: meta))
        }
        return out
    }

    static func activityType(_ sport: String) -> HKWorkoutActivityType {
        switch HealthKitMapper.workoutActivityTypeName(sport: sport) {
        case "Running": return .running
        case "Walking": return .walking
        case "Cycling": return .cycling
        case "TraditionalStrengthTraining": return .traditionalStrengthTraining
        case "HighIntensityIntervalTraining": return .highIntensityIntervalTraining
        case "Yoga": return .yoga
        case "Swimming": return .swimming
        case "Hiking": return .hiking
        default: return .other
        }
    }

    private static func isNOOPSource(_ sample: HKObject) -> Bool {
        let id = sample.sourceRevision.source.bundleIdentifier.lowercased()
        return id.contains("noopapp") || id.contains("noop")
    }

    private static func noon(_ ymd: String) -> Date? {
        let p = ymd.split(separator: "-")
        guard p.count == 3, let y = Int(p[0]), let m = Int(p[1]), let d = Int(p[2]) else { return nil }
        return Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: 12))
    }
}
