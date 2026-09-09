import Foundation
import StrandImport
import WhoopStore

/// Pure HealthKit ↔ StrandImport mapping. No HealthKit import — Strand compiles
/// on Mac, and tests run there. Live `HKSample` objects are converted to these
/// primitives by `HealthKitBridge` (iOS only).
enum HealthKitMapper {

    /// HKCategoryValueSleepAnalysis raw values (iOS 16+).
    static func sleepStage(fromCategoryValue value: Int) -> SleepStage {
        SleepStage.from(rawValue: String(value))
    }

    /// NOOP / SleepStager labels → HKCategoryValueSleepAnalysis integers.
    static func categoryValue(stageLabel: String) -> Int {
        switch stageLabel.lowercased() {
        case "wake", "awake": return 2
        case "light": return 3          // AsleepCore
        case "deep": return 4
        case "rem": return 5
        case "inbed", "in-bed", "in_bed": return 0
        default: return 1               // AsleepUnspecified
        }
    }

    static func stageLabel(fromStage stage: SleepStage) -> String {
        switch stage {
        case .inBed: return "inBed"
        case .asleepUnspecified: return "asleep"
        case .asleepCore: return "light"
        case .asleepDeep: return "deep"
        case .asleepREM: return "rem"
        case .awake: return "wake"
        case .unknown: return "unknown"
        }
    }

    static func relevantTypes() -> Set<String> {
        AppleHealthImporter.relevantTypes
    }

    static func strippedType(_ raw: String) -> String {
        AppleHealthImporter.stripPrefix(raw)
    }

    /// Sport string stored on WorkoutRow / HealthWorkout.
    static func sportName(fromActivityType raw: String) -> String {
        let s = AppleHealthImporter.stripPrefix(raw)
        return s.isEmpty ? "Workout" : s
    }

    /// HKWorkoutActivityType name (prefix stripped) for a NOOP sport.
    static func workoutActivityTypeName(sport: String) -> String {
        switch sport.lowercased() {
        case "running": return "Running"
        case "walking": return "Walking"
        case "cycling": return "Cycling"
        case "strength training", "strength": return "TraditionalStrengthTraining"
        case "hiit": return "HighIntensityIntervalTraining"
        case "yoga": return "Yoga"
        case "swimming": return "Swimming"
        case "hiking": return "Hiking"
        default: return "Other"
        }
    }

    /// Recovery is not a HealthKit quantity type. It rides as metadata on the
    /// sleep sample Health already shows, so the score is in the on-device
    /// Health store without inventing a fake HR/weight sample.
    static func recoveryMetadata(score: Double) -> [String: Double] {
        ["NOOPRecovery": score]
    }

    static func cachedSleepSessions(from intervals: [SleepStageInterval]) -> [CachedSleepSession] {
        struct Acc {
            var start: Date
            var end: Date
            var deep = 0.0, rem = 0.0, core = 0.0, unspecified = 0.0, awake = 0.0, inBed = 0.0
        }
        var byDay: [String: Acc] = [:]
        for iv in intervals {
            let minutes = max(0, iv.end.timeIntervalSince(iv.start)) / 60.0
            let day = AppleHealthAggregator.localDay(iv.end, tzOffsetMin: iv.tzOffsetMin)
            var a = byDay[day] ?? Acc(start: iv.start, end: iv.end)
            a.start = min(a.start, iv.start)
            a.end = max(a.end, iv.end)
            switch iv.stage {
            case .asleepDeep: a.deep += minutes
            case .asleepREM: a.rem += minutes
            case .asleepCore: a.core += minutes
            case .asleepUnspecified: a.unspecified += minutes
            case .awake: a.awake += minutes
            case .inBed: a.inBed += minutes
            case .unknown: break
            }
            byDay[day] = a
        }
        return byDay.values.compactMap { a in
            let light = a.core + a.unspecified
            let asleep = light + a.deep + a.rem
            let inBed = max(a.inBed, asleep + a.awake)
            guard asleep > 0 || inBed > 0 else { return nil }
            let dict: [String: Double] = [
                "light": light, "deep": a.deep, "rem": a.rem, "awake": a.awake
            ]
            let json = (try? JSONSerialization.data(withJSONObject: dict))
                .flatMap { String(data: $0, encoding: .utf8) }
            let efficiency = inBed > 0 ? asleep / inBed : nil
            return CachedSleepSession(
                startTs: Int(a.start.timeIntervalSince1970),
                endTs: Int(a.end.timeIntervalSince1970),
                efficiency: inBed > 0 ? efficiency : nil,
                restingHr: nil, avgHrv: nil, stagesJSON: json)
        }
        .sorted { $0.startTs < $1.startTs }
    }

    /// Segments from on-device stagesJSON (array shape) for writing to Health.
    static func writeSegments(from stagesJSON: String?) -> [(label: String, start: Int, end: Int)] {
        guard let json = stagesJSON, let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) else { return [] }
        if let segs = obj as? [[String: Any]] {
            return segs.compactMap { s in
                let start = (s["start"] as? NSNumber)?.intValue
                    ?? (s["start"] as? Int)
                let end = (s["end"] as? NSNumber)?.intValue
                    ?? (s["end"] as? Int)
                guard let start, let end, end > start else { return nil }
                let label = (s["stage"] as? String) ?? "light"
                return (label, start, end)
            }
        }
        return []
    }
}
