import SwiftUI
import StrandDesign

/// Start / stop a live workout. Phone GPS on runs/walks/rides/hikes, WHOOP HR if bonded.
/// There is no Watch app and no live HealthKit — an Apple Watch is not a source.
struct LiveSessionView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var repo: Repository
    @EnvironmentObject var live: LiveState
    var onSaved: (() -> Void)? = nil

    var body: some View {
        RecorderBody(session: model.session, onSaved: onSaved)
    }
}

private struct RecorderBody: View {
    @ObservedObject var session: LiveSessionRecorder
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var repo: Repository
    @EnvironmentObject var live: LiveState
    var onSaved: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var saving = false

    var body: some View {
        ScreenScaffold(title: "Live session",
                       subtitle: session.running ? "In progress — keep the phone with you." : "Start, move, stop. Saved to your log.") {
            if session.running {
                liveCard
                metricsGrid
                gpsLine
                stopRow
            } else {
                DataPendingNote(
                    title: "Phone GPS. Strap HR. No Apple Watch.",
                    message: "Running, walking, cycling and hiking use this iPhone’s GPS for distance. Heart rate comes from the WHOOP strap if it is bonded on Live. An Apple Watch is not connected — there is no Watch app and no live HealthKit.",
                    symbol: "figure.run")
                setupCard
                startButton
            }
            if let err = session.error {
                Text(err)
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.statusCritical)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var setupCard: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("SPORT").strandOverline()
                Picker("Sport", selection: $session.sport) {
                    ForEach(WorkoutSport.allCases) { s in
                        Text(s.rawValue).tag(s.rawValue)
                    }
                }
                #if os(iOS)
                .pickerStyle(.menu)
                #endif
                .accessibilityLabel("Sport")

                Text(gpsHint)
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    SourceBadge(live.bonded ? "Strap HR" : "No strap",
                                tint: live.bonded ? StrandPalette.accent : StrandPalette.textTertiary)
                    if session.usesGPS {
                        SourceBadge("Phone GPS", tint: StrandPalette.metricCyan)
                    }
                    if session.usesSteps {
                        SourceBadge("Phone steps", tint: StrandPalette.metricAmber)
                    }
                }
            }
        }
    }

    private var gpsHint: String {
        if session.usesGPS {
            return "This sport records distance from the iPhone. Allow location when asked; keep the phone on you. Lock the screen if you want — GPS can keep running."
        }
        return "This sport does not use GPS. Duration and strap heart rate still save."
    }

    private var startButton: some View {
        Button {
            if live.bonded { model.startRealtimeHR() }
            session.start(sport: session.sport, hr: { model.bpm }, profile: model.profile)
        } label: {
            Label("Start session", systemImage: "play.fill")
                .font(StrandFont.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .tint(StrandPalette.accent)
        .accessibilityLabel("Start live workout session")
    }

    private var liveCard: some View {
        NoopCard {
            VStack(spacing: 6) {
                Text(session.sport.uppercased()).strandOverline()
                Text(session.elapsedLabel)
                    .font(StrandFont.number(56))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(live.bonded ? (session.lastBpm.map { "\($0) bpm" } ?? "Strap · waiting for HR") : "No strap HR")
                    .font(StrandFont.subhead)
                    .foregroundStyle(live.bonded ? StrandPalette.metricRose : StrandPalette.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: NoopMetrics.gap)],
                  spacing: NoopMetrics.gap) {
            StatTile(label: "Distance", value: session.distanceLabel,
                     caption: session.usesGPS ? "phone GPS" : "not tracked",
                     accent: StrandPalette.metricCyan)
            StatTile(label: "Pace", value: session.paceLabel,
                     caption: "from GPS",
                     accent: StrandPalette.accent)
            StatTile(label: "Avg HR", value: session.avgHr.map { "\($0)" } ?? "—",
                     caption: "bpm",
                     accent: StrandPalette.metricRose)
            StatTile(label: "Peak HR", value: session.maxHr.map { "\($0)" } ?? "—",
                     caption: "bpm",
                     accent: StrandPalette.metricRose)
            if session.usesSteps {
                StatTile(label: "Steps", value: session.steps > 0 ? "\(session.steps)" : "—",
                         caption: "this iPhone",
                         accent: StrandPalette.metricAmber)
            }
        }
    }

    private var gpsLine: some View {
        Text(session.gpsNote)
            .font(StrandFont.footnote)
            .foregroundStyle(StrandPalette.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var stopRow: some View {
        VStack(spacing: 12) {
            Button {
                Task { await stopAndSave() }
            } label: {
                Label(saving ? "Saving…" : "Stop and save", systemImage: "stop.fill")
                    .font(StrandFont.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(StrandPalette.statusCritical)
            .disabled(saving)
            .accessibilityLabel("Stop and save live workout")

            Button {
                session.discard()
                dismiss()
            } label: {
                Text("Discard session")
                    .font(StrandFont.body)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .disabled(saving)
            .accessibilityLabel("Discard live workout without saving")
        }
    }

    @MainActor
    private func stopAndSave() async {
        saving = true
        defer { saving = false }
        let ok = await session.save(into: repo)
        if ok {
            onSaved?()
            dismiss()
        } else {
            session.error = "Could not save this session. Try Stop and save again."
        }
    }
}

struct LiveSessionEntryLink: View {
    var caption: String = "Start / stop · GPS on runs · strap HR"
    var onSaved: (() -> Void)? = nil

    var body: some View {
        NavigationLink {
            LiveSessionView(onSaved: onSaved)
        } label: {
            NoopCard {
                HStack(spacing: 12) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(StrandPalette.accent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Live session")
                            .font(StrandFont.headline)
                            .foregroundStyle(StrandPalette.textPrimary)
                        Text(caption)
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(StrandPalette.textTertiary)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Start a live workout session")
    }
}
