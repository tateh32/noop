import Foundation

/// Phone vs Mac resource caps. The iPhone target compiles the Mac screens, so
/// without these the dashboard loads years of series, scores 21 nights of raw
/// HR on the main actor, and keeps every tab alive — which is why a sideload
/// feels frozen and then dies.
enum PhoneBudget {
    static var isPhone: Bool {
        #if os(iOS)
        true
        #else
        false
        #endif
    }

    /// How far back dashboard sparkline queries go. Mac still reads full history.
    static var sparkQueryDays: Int { isPhone ? 90 : 4000 }

    /// Daily rows kept in `Repository.days`. Today/Sleep/Readiness only need months,
    /// not a decade of WHOOP history in RAM.
    static var dashboardDays: Int { isPhone ? 400 : 4000 }

    /// Sleep sessions loaded into `Repository.sleeps`.
    static var sleepCacheLimit: Int { isPhone ? 90 : 4000 }

    /// Workout rows fetched for the Today grid.
    static var workoutQueryDays: Int { isPhone ? 120 : 4000 }

    /// Nights the on-device scorer walks per pass.
    static var intelligenceDays: Int { isPhone ? 3 : 21 }

    /// Per-stream sample cap for one intelligence night (1 Hz × ~7 h ≈ 25k).
    static var intelligenceSampleLimit: Int { isPhone ? 24_000 : 200_000 }

    /// Year-heat cells. A full multi-year strip is thousands of SwiftUI views.
    static var heatStripMaxDays: Int { isPhone ? 180 : 4000 }

    /// Chart marks before we stride-downsample.
    static var chartMaxPoints: Int { isPhone ? 160 : 800 }

    /// Strap log lines kept in LiveState.
    static var liveLogCap: Int { isPhone ? 40 : 200 }

    /// Skip nights that already have a recovery score (import or a prior pass).
    /// Per-day, not all-or-nothing — new strap nights still get scored.
    static var skipScoringWhenImported: Bool { isPhone }
}
