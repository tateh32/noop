import Foundation
import WhoopProtocol
import StrandAnalytics

/// Pure smart-wake policy. The firmware alarm is always the safety net at the
/// target time; this layer may buzz *early* only when every gate holds:
/// enabled, phone still connected, inside the user window, current stage is
/// light, and we have not already fired for this target.
enum SmartWake {

    enum Stage: String, Equatable {
        case wake, light, deep, rem, unknown

        init(label: String) {
            self = Stage(rawValue: label) ?? .unknown
        }

        /// Early fire is light only — not REM, not deep, not an unknown guess.
        var isLightPhase: Bool { self == .light }
    }

    enum Decision: Equatable {
        /// Disabled, already fired, or the strap is not connected — do nothing.
        case none
        /// Before the window, or in the window but not on a light phase.
        case wait
        /// Inside the window, connected, light phase — buzz now.
        case fireEarly
        /// At or past the target. Firmware handles the buzz; we never fire early.
        case firmwareAtTarget
    }

    struct Snapshot: Equatable {
        var now: Date
        var targetWake: Date
        var windowMinutes: Int
        var enabled: Bool
        var connected: Bool
        var alreadyFired: Bool
        var stage: Stage
    }

    static let firedKey = "noop.smartWake.firedTarget"

    static func nextTargetWake(minutesFromMidnight: Int, now: Date,
                               calendar: Calendar = .current) -> Date {
        let h = max(0, minutesFromMidnight) / 60
        let m = max(0, minutesFromMidnight) % 60
        var next = calendar.date(bySettingHour: h, minute: m, second: 0, of: now) ?? now
        if next <= now { next = calendar.date(byAdding: .day, value: 1, to: next) ?? next }
        return next
    }

    static func windowStart(target: Date, windowMinutes: Int) -> Date {
        target.addingTimeInterval(-TimeInterval(max(0, windowMinutes) * 60))
    }

    /// True from `leadS` before the window until the target (exclusive).
    static func isInOrNearWindow(now: Date, target: Date, windowMinutes: Int,
                                leadS: TimeInterval = 300) -> Bool {
        let start = windowStart(target: target, windowMinutes: windowMinutes)
            .addingTimeInterval(-leadS)
        return now >= start && now < target
    }

    static func decide(_ s: Snapshot) -> Decision {
        guard s.enabled else { return .none }
        if s.alreadyFired { return .none }
        if s.now >= s.targetWake { return .firmwareAtTarget }
        // Early fire is a connected-phone feature. Firmware still fires at target
        // if the phone is gone — that is the safety net, not an early buzz.
        guard s.connected else { return .none }
        if s.windowMinutes <= 0 { return .wait }
        let start = windowStart(target: s.targetWake, windowMinutes: s.windowMinutes)
        guard s.now >= start else { return .wait }
        if s.stage.isLightPhase { return .fireEarly }
        return .wait
    }

    /// Classify the current epoch from a trailing live window.
    static func classify(now: Date, hr: [HRSample], gravity: [GravitySample]) -> Stage {
        Stage(label: SleepStager.currentStage(now: Int(now.timeIntervalSince1970),
                                              hr: hr, gravity: gravity))
    }

    static func rememberFired(target: Date, defaults: UserDefaults = .standard) {
        defaults.set(target.timeIntervalSince1970, forKey: firedKey)
    }

    static func forgetFired(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: firedKey)
    }

    /// True when we already buzzed early for this same target (within one second).
    static func alreadyFired(for target: Date, defaults: UserDefaults = .standard) -> Bool {
        guard let t = defaults.object(forKey: firedKey) as? Double else { return false }
        return abs(t - target.timeIntervalSince1970) < 1
    }
}
