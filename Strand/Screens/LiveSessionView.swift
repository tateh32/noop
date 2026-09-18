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
        #if os(iOS)
        RecorderBody(session: model.session, onSaved: onSaved)
            .navigationTitle("Train")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink {
                        LiveView()
                    } label: {
                        Label("Strap", systemImage: "waveform.path.ecg")
                    }
                    .accessibilityLabel("WHOOP strap live heart rate")
                }
            }
        #else
        RecorderBody(session: model.session, onSaved: onSaved)
        #endif
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
        ScreenScaffold(title: "Train",
                       subtitle: session.running ? "In progress — keep the phone with you." : "Start, move, stop. Saved to your log.") {
            if session.running {
                liveCard
                metricsGrid
                gpsLine
                stopRow
            } else {
                DataPendingNote(
                    title: "This is Start / Stop. Phone GPS. Strap HR.",
                    message: "Tap Start session below. Running, walking, cycling and hiking use this iPhone’s GPS. Heart rate comes from the WHOOP strap if it is bonded — Strap in the top right, or More → Live. An Apple Watch is not connected.",
                    symbol: "figure.run")
                setupCard
                startButton
                #if os(iOS)
                strapLink
                #endif
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
            return "This sport records distance from the iPhone. Allow location when asked (Always keeps it going after you lock the screen). Keep the phone on you."
        }
        return "This sport does not use GPS. Duration and strap heart rate still save."
    }

    private var startButton: some View {
        Button {
            if live.bonded { model.startRealtimeHR() }
            session.start(sport: session.sport, hr: { model.bpm }, profile: model.profile)
        } label: {
            LiveSessionPaintedLabel(title: "Start session", systemImage: "play.fill")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Start live workout session")
    }

    #if os(iOS)
    private var strapLink: some View {
        NavigationLink {
            LiveView()
        } label: {
            NoopCard {
                HStack(spacing: 12) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(StrandPalette.accent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("WHOOP strap")
                            .font(StrandFont.headline)
                            .foregroundStyle(StrandPalette.textPrimary)
                        Text(live.bonded ? "Bonded — heart rate will record" : "Not bonded — tap to scan & connect")
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
        .accessibilityLabel("Open WHOOP strap live heart rate")
    }
    #endif

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

/// Filled accent control. `NavigationLink` + `.borderedProminent` can render empty on iOS 16.
struct LiveSessionPaintedLabel: View {
    var title: String
    var systemImage: String = "play.fill"
    @Environment(\.noopAppearance) private var appearance

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
            Text(title)
        }
        .font(StrandFont.headline)
        .foregroundStyle(appearance.isGlass ? Color.black.opacity(0.85) : Color.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(appearance.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
