import Foundation

/// Stage minutes for one night, decoded from the `stagesJSON` column.
///
/// That column has two producers writing two different shapes, which is why the
/// Sleep screen could show "no nights yet" for a night it had already scored:
///
/// - A WHOOP / Apple import writes a **minutes dict** — `{"light":210,"deep":80,…}`.
///   The export has no per-epoch timeline, only totals.
/// - On-device scoring (`AnalyticsEngine.encodeStages`) writes a **segment array** —
///   `[{"start":…,"end":…,"stage":"deep"}, …]` from the hypnogram.
///
/// Pure and platform-free so it can be unit-tested without a view.
struct SleepStageBreakdown: Equatable {
    var awake: Double
    var light: Double
    var deep: Double
    var rem: Double

    /// All stages including awake — time in bed, in minutes.
    var total: Double { awake + light + deep + rem }
    /// Time asleep, in minutes.
    var asleep: Double { light + deep + rem }

    init(awake: Double, light: Double, deep: Double, rem: Double) {
        self.awake = awake; self.light = light; self.deep = deep; self.rem = rem
    }

    /// Decode either shape. Returns nil for absent, malformed, or all-zero input.
    static func decode(_ json: String?) -> SleepStageBreakdown? {
        guard let json, let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }
        if let dict = obj as? [String: Any] { return fromMinutes(dict) }
        if let segments = obj as? [[String: Any]] { return fromSegments(segments) }
        return nil
    }

    static func fromMinutes(_ dict: [String: Any]) -> SleepStageBreakdown? {
        let s = SleepStageBreakdown(awake: number(dict["awake"]) ?? 0,
                                    light: number(dict["light"]) ?? 0,
                                    deep: number(dict["deep"]) ?? 0,
                                    rem: number(dict["rem"]) ?? 0)
        return s.total > 0 ? s : nil
    }

    /// Sum segment durations per stage. `SleepStager` emits
    /// "wake" | "light" | "deep" | "rem"; unknown labels count as light.
    static func fromSegments(_ segments: [[String: Any]]) -> SleepStageBreakdown? {
        var s = SleepStageBreakdown(awake: 0, light: 0, deep: 0, rem: 0)
        for seg in segments {
            guard let start = number(seg["start"]), let end = number(seg["end"]),
                  end > start else { continue }
            let minutes = (end - start) / 60.0
            switch seg["stage"] as? String {
            case "deep": s.deep += minutes
            case "rem": s.rem += minutes
            case "wake", "awake": s.awake += minutes
            default: s.light += minutes
            }
        }
        return s.total > 0 ? s : nil
    }

    private static func number(_ any: Any?) -> Double? {
        if let n = any as? NSNumber { return n.doubleValue }
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        return nil
    }
}
