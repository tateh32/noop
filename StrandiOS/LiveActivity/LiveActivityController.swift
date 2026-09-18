import Foundation

#if os(iOS) && canImport(ActivityKit)
import ActivityKit
#endif

/// Starts / updates / ends the workout Live Activity. iOS 16.1+; no-op elsewhere.
enum LiveActivityController {
    #if os(iOS) && canImport(ActivityKit)
    private static var current: Activity<WorkoutActivityAttributes>?
    private static var lastPushAt: TimeInterval = 0
    private static let minPushInterval: TimeInterval = 5
    #endif

    static func start(sport: String, startedAt: Date, bpm: Int?, elapsedS: Int) {
        #if os(iOS) && canImport(ActivityKit)
        guard #available(iOS 16.1, *) else { return }
        lastPushAt = 0
        let state = WorkoutLiveActivityState(elapsedS: elapsedS, bpm: bpm, sport: sport)
        let attrs = WorkoutActivityAttributes(sport: sport, startedAt: startedAt)
        if let existing = Activity<WorkoutActivityAttributes>.activities.first {
            current = existing
            Task { await Self.push(existing, state: state) }
            return
        }
        do {
            if #available(iOS 16.2, *) {
                current = try Activity.request(attributes: attrs,
                                              content: .init(state: state, staleDate: nil),
                                              pushType: nil)
            } else {
                current = try Activity.request(attributes: attrs, contentState: state,
                                               pushType: nil)
            }
        } catch {
            current = nil
        }
        #endif
    }

    static func update(elapsedS: Int, bpm: Int?, sport: String) {
        #if os(iOS) && canImport(ActivityKit)
        guard #available(iOS 16.1, *) else { return }
        let now = Date().timeIntervalSince1970
        guard now - lastPushAt >= minPushInterval else { return }
        let state = WorkoutLiveActivityState(elapsedS: elapsedS, bpm: bpm, sport: sport)
        let activity = current ?? Activity<WorkoutActivityAttributes>.activities.first
        current = activity
        guard let activity else { return }
        lastPushAt = now
        Task { await Self.push(activity, state: state) }
        #endif
    }

    static func end() {
        #if os(iOS) && canImport(ActivityKit)
        guard #available(iOS 16.1, *) else { return }
        let activities = Activity<WorkoutActivityAttributes>.activities
        current = nil
        lastPushAt = 0
        Task {
            for a in activities {
                if #available(iOS 16.2, *) {
                    await a.end(nil, dismissalPolicy: .immediate)
                } else {
                    await a.end(using: nil, dismissalPolicy: .immediate)
                }
            }
        }
        #endif
    }

    #if os(iOS) && canImport(ActivityKit)
    @available(iOS 16.1, *)
    private static func push(_ activity: Activity<WorkoutActivityAttributes>,
                              state: WorkoutLiveActivityState) async {
        lastPushAt = Date().timeIntervalSince1970
        if #available(iOS 16.2, *) {
            await activity.update(.init(state: state, staleDate: nil))
        } else {
            await activity.update(using: state)
        }
    }
    #endif
}
