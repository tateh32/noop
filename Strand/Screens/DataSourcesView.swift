import SwiftUI
import UniformTypeIdentifiers
import StrandDesign

struct DataSourcesView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var repo: Repository
    @EnvironmentObject var live: LiveState
    @State private var picking = false
    @State private var pickingApple = false
    @State private var confirmStartFresh = false

    #if os(iOS)
    /// iOS Files often presents a WHOOP zip as generic data, not `public.zip-archive`.
    private static let importTypes: [UTType] = [.zip, .data, .item]
    private static let deviceWord = "this iPhone"
    private static let whoopBlurb = "Import your full WHOOP history from a data export (.zip). Save it to Files on this iPhone (Safari download or AirDrop), then pick it here. Get one at app.whoop.com → Data Management."
    #else
    private static let importTypes: [UTType] = [.zip, .folder]
    private static let deviceWord = "this Mac"
    private static let whoopBlurb = "Import your full WHOOP history — recovery, strain, sleep, workouts — from a data export (.zip). Works for WHOOP 4.0, 5.0 and MG. Get one at app.whoop.com → Data Management."
    #endif

    var body: some View {
        ScreenScaffold(title: "Data Sources",
                       subtitle: "Everything stays on \(Self.deviceWord). Bring your history in once, then it's yours.") {
            // Each importer lives on its OWN card. Two `.fileImporter` modifiers on the
            // same view silently collapse to one in SwiftUI — which is why the WHOOP
            // button used to do nothing while Apple Health worked (issue #5).
            whoopCard
                .fileImporter(isPresented: $picking,
                              allowedContentTypes: Self.importTypes,
                              allowsMultipleSelection: false) { result in
                    if case .success(let urls) = result, let url = urls.first {
                        model.importWhoop(url: url)
                    }
                }
            appleHealthCard
                .fileImporter(isPresented: $pickingApple,
                              allowedContentTypes: Self.importTypes,
                              allowsMultipleSelection: false) { result in
                    if case .success(let urls) = result, let url = urls.first {
                        model.importAppleHealth(url: url)
                    }
                }
            #if os(iOS)
            healthKitCard
            #endif
            liveCard
            startFreshCard
        }
        .alert("Start over?", isPresented: $confirmStartFresh) {
            Button("Cancel", role: .cancel) { }
            Button("Clear history", role: .destructive) {
                model.startFresh()
            }
        } message: {
            Text("This clears imported and computed scores (recovery, sleep, workouts, Apple Health) so you can reimport cleanly. Live samples from the strap stay on \(Self.deviceWord).")
        }
    }

    private var whoopCard: some View {
        card(title: "WHOOP Export", icon: "square.and.arrow.down.fill",
             subtitle: Self.whoopBlurb) {
            HStack(spacing: 12) {
                Button {
                    picking = true
                } label: {
                    Label(model.importing ? "Importing…" : "Choose export…",
                          systemImage: "tray.and.arrow.down")
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(StrandPalette.accent)
                .disabled(model.importing)
                if model.importing { ProgressView().controlSize(.small) }
            }
            if let s = model.importSummary {
                Text(s)
                    .font(StrandFont.subhead)
                    .foregroundStyle(Self.summaryColor(s))
            }
            Text("\(repo.days.count) days · \(repo.sleeps.count) sleeps stored")
                .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
        }
    }

    #if os(iOS)
    private var healthKitCard: some View {
        HealthKitSyncCard()
    }
    #endif

    private var appleHealthCard: some View {
        card(title: "Apple Health", icon: "heart.fill",
             subtitle: "Import an Apple Health export (Health app → profile → Export All Health Data → export.zip). 7 years of HR, HRV, sleep, SpO₂, steps and more — streamed locally. Large exports take a minute or two.") {
            HStack(spacing: 12) {
                Button { pickingApple = true } label: {
                    Label(model.importing ? "Working…" : "Choose export.zip…", systemImage: "tray.and.arrow.down")
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent).tint(StrandPalette.accent)
                .disabled(model.importing)
                if model.importing { ProgressView().controlSize(.small) }
            }
        }
    }

    private var startFreshCard: some View {
        card(title: "Start over", icon: "arrow.counterclockwise",
             subtitle: "If a previous import looks empty or half-loaded, clear the local history and bring it in again. This is a data reset, not a rewrite — the importers stay.") {
            Button {
                confirmStartFresh = true
            } label: {
                Label("Clear imported history…", systemImage: "trash")
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.bordered)
            .tint(StrandPalette.statusCritical)
            .disabled(model.importing)
        }
    }

    private var liveCard: some View {
        card(title: "WHOOP Strap (Live BLE)", icon: "antenna.radiowaves.left.and.right",
             subtitle: "Pairs directly with your strap over Bluetooth — no WHOOP app, no cloud.") {
            HStack(spacing: 8) {
                // Three-state, consistent with the Live screen's connection pill — a connected-but-
                // not-yet-streaming strap (e.g. an experimental WHOOP 5/MG link) no longer reads as
                // "Not connected" on one screen and "Connected" on another (issue #8).
                let (dot, label): (Color, String) =
                    live.bonded ? (StrandPalette.statusPositive, "Bonded — streaming.")
                    : live.connected ? (StrandPalette.statusWarning, "Connected.")
                    : (StrandPalette.statusCritical, "Not connected — open Live to pair.")
                Circle().fill(dot).frame(width: 8, height: 8)
                Text(label).font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
            }
        }
    }

    private static func summaryColor(_ s: String) -> Color {
        let lower = s.lowercased()
        if lower.contains("failed") || lower.contains("couldn't") || lower.contains("no scored") {
            return StrandPalette.statusCritical
        }
        return StrandPalette.statusPositive
    }

    @ViewBuilder
    private func card<C: View>(title: String, icon: String, subtitle: String,
                              @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon).foregroundStyle(StrandPalette.accent)
                Text(title).font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
            }
            Text(subtitle).font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StrandPalette.surfaceRaised, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(StrandPalette.hairline))
    }
}

#if os(iOS)
private struct HealthKitSyncCard: View {
    @EnvironmentObject var healthKit: HealthKitBridge
    @EnvironmentObject var model: AppModel

    var body: some View {
        SettingsSection(
            icon: "heart.circle.fill",
            title: "Apple Health live",
            blurb: "Opt-in, on this iPhone only. NOOP reads sleep and workouts from Health, and writes sleep, workouts, heart rate, HRV and recovery (recovery is stored as metadata on last night — Health has no recovery type). Nothing leaves the device."
        ) {
            VStack(alignment: .leading, spacing: 8) {
                SettingsToggleRow(
                    label: "Sync with Apple Health",
                    help: healthKit.isAvailable
                        ? "Turn on, then allow Health access. The HealthKit capability must be enabled on your Apple team in Xcode."
                        : "HealthKit is not available on this device.",
                    isOn: $healthKit.enabled)
                if let s = healthKit.status {
                    Text(s).font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let e = healthKit.lastError {
                    Text(e).font(StrandFont.footnote).foregroundStyle(StrandPalette.statusCritical)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onChange(of: healthKit.enabled) { on in
            if on { Task { await model.syncHealthKit() } }
        }
    }
}
#endif
