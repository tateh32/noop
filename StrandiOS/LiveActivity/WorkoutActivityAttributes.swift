import Foundation
import ActivityKit

struct WorkoutActivityAttributes: ActivityAttributes {
    typealias ContentState = WorkoutLiveActivityState

    var sport: String
    var startedAt: Date
}
