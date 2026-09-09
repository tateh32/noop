import SwiftUI
import StrandDesign

/// Automations — turn the strap's physical inputs (double-tap, wrist on/off) and live biometrics
/// into Mac actions and haptic coaching. All on-device.
struct AutomationsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var behavior: BehaviorStore
    @EnvironmentObject var live: LiveState

    var body: some View {
        ScreenScaffold(title: "Automations",
                       subtitle: "Make the strap do things — tap to act, walk away to lock, train by feel.") {
            doubleTapCard
            wearCard
            coachingCard
            alarmPointer
        }
    }

    // MARK: - Double tap

    private var doubleTapCard: some View {
        SettingsSection(icon: "hand.tap.fill", title: "Double-tap",
                 blurb: "Double-tap the strap to trigger an action on \(DeviceCopy.here). (The strap exposes a single double-tap gesture.)") {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("When I double-tap").font(StrandFont.body).foregroundStyle(StrandPalette.textPrimary)
                    Spacer()
                    Picker("", selection: $behavior.doubleTapAction) {
                        ForEach(MacActionKind.availableCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                }
                if behavior.doubleTapAction == .runShortcut {
                    shortcutField("Shortcut name", text: $behavior.doubleTapShortcut)
                }
                HStack {
                    Button {
                        model.runMacAction(behavior.doubleTapAction, shortcut: behavior.doubleTapShortcut)
                    } label: { Label("Test action", systemImage: "play.fill") }
                    .buttonStyle(.bordered).tint(StrandPalette.accent)
                    .disabled(behavior.doubleTapAction == .none)
                    Spacer()
                    StatePill(live.bonded ? "Strap bonded" : "Strap not connected",
                              tone: live.bonded ? .positive : .warning, showsDot: true)
                }
                if !model.moments.isEmpty {
                    rowDivider
                    momentsView
                }
            }
        }
    }

    private var momentsView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Recent moments").strandOverline()
                Spacer()
                Button("Clear") {
                    model.moments.removeAll()
                    UserDefaults.standard.removeObject(forKey: "moments")
                }
                .buttonStyle(.plain).font(StrandFont.caption).foregroundStyle(StrandPalette.accent)
            }
            ForEach(Array(model.moments.suffix(5).reversed().enumerated()), id: \.offset) { _, d in
                Text(Self.momentFormatter.string(from: d))
                    .font(StrandFont.captionNumber).foregroundStyle(StrandPalette.textSecondary)
            }
        }
    }
    private static let momentFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE d MMM · HH:mm"; return f
    }()

    // MARK: - Wear & presence

    private var wearCard: some View {
        SettingsSection(icon: "figure.walk.motion", title: "Wear & presence",
                 blurb: "React when the strap comes off or goes on.") {
            VStack(spacing: 0) {
                #if os(macOS)
                SettingsToggleRow(label: "Lock the Mac when I take the strap off",
                          help: "Fires the moment the strap leaves your wrist. macOS reserves true auto-UNLOCK for Apple Watch — this can lock, not unlock.",
                          isOn: $behavior.autoLockOnWristOff)
                rowDivider
                #endif
                shortcutFieldRow("Run a Shortcut when taken off",
                                 help: "Presence automation — set a Focus, pause media, set away…",
                                 text: $behavior.wristOffShortcut)
                rowDivider
                shortcutFieldRow("Run a Shortcut when put back on",
                                 help: "Reverse the above when you return.",
                                 text: $behavior.wristOnShortcut)
            }
        }
    }

    // MARK: - Coaching

    private var coachingCard: some View {
        SettingsSection(icon: "bolt.heart.fill", title: "Haptic coaching",
                 blurb: "Train by feel — the strap buzzes so you don't have to watch a screen.") {
            VStack(spacing: 0) {
                SettingsToggleRow(label: "HR-zone coaching",
                          help: "Buzz when you hit your top zone (ease off) and again when you recover. Uses your max HR from Settings.",
                          isOn: $behavior.zoneCoaching)
                rowDivider
                SettingsToggleRow(label: "Resting stress nudge (experimental)",
                          help: "A gentle buzz when your HRV drops while your heart rate is calm — a cue to take a paced breath. Rate-limited to once every 15 minutes; off by default.",
                          isOn: $behavior.stressNudge)
            }
        }
    }

    // MARK: - Smart alarm (now lives on Sleep)

    private var alarmPointer: some View {
        SettingsSection(icon: "alarm.fill", title: "Smart alarm",
                 blurb: "The smart alarm moved to the Sleep screen, next to last night — it is a sleep decision, not a desk automation.") {
            Text("Open Sleep to set your wake time and light-sleep window.")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Helpers

    private func shortcutField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.roundedBorder)
            .font(StrandFont.body)
            .frame(maxWidth: 320)
    }

    private func shortcutFieldRow(_ label: String, help: String, text: Binding<String>) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(StrandFont.body).foregroundStyle(StrandPalette.textPrimary)
                Text(help).font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            shortcutField("Shortcut name", text: text)
        }
        .frame(minHeight: 42).padding(.vertical, 4)
    }

    private var rowDivider: some View { SettingsRowDivider() }
}

// The card/row idiom moved to SettingsComponents.swift so Sleep's smart alarm can
// use the same surfaces.
