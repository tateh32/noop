import SwiftUI
import WidgetKit
import ActivityKit

struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            WorkoutLockScreen(state: context.state, startedAt: context.attributes.startedAt)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.sport)
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.bpm.map { "\($0)" } ?? "—")
                        .font(.title2.monospacedDigit())
                    + Text(" bpm").font(.caption)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(WorkoutLiveActivityState.elapsedLabel(context.state.elapsedS))
                        .font(.title.monospacedDigit())
                }
            } compactLeading: {
                Image(systemName: "figure.run")
            } compactTrailing: {
                Text(context.state.bpm.map { "\($0)" } ?? "—")
                    .font(.caption.monospacedDigit())
            } minimal: {
                Image(systemName: "figure.run")
            }
        }
    }
}

private struct WorkoutLockScreen: View {
    let state: WorkoutLiveActivityState
    let startedAt: Date

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(state.sport.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(WorkoutLiveActivityState.elapsedLabel(state.elapsedS))
                    .font(.system(size: 28, weight: .semibold).monospacedDigit())
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(state.bpm.map { "\($0)" } ?? "—")
                    .font(.system(size: 28, weight: .semibold).monospacedDigit())
                Text("bpm")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .activityBackgroundTint(Color.black.opacity(0.35))
        .activitySystemActionForegroundColor(.white)
    }
}
