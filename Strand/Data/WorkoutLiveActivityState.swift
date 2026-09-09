import Foundation

/// Lock-screen Live Activity payload. Shared by the app and the widget
/// extension (same file compiled into both). Extracted so tests can encode
/// it without ActivityKit.
struct WorkoutLiveActivityState: Codable, Hashable, Equatable {
    var elapsedS: Int
    var bpm: Int?
    var sport: String

    static func elapsedLabel(_ elapsedS: Int) -> String {
        let h = elapsedS / 3600
        let m = (elapsedS % 3600) / 60
        let s = elapsedS % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}
