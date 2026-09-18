import SwiftUI
import StrandDesign

/// Root — the sidebar shell, with the first-run onboarding/pairing wizard overlaid until complete,
/// and a "What's New" changelog sheet shown automatically after an update.
struct ContentView: View {
    @AppStorage("noop.onboarded") private var onboarded = false
    @AppStorage("noop.lastSeenChangelogVersion") private var lastSeenChangelog = ""
    @AppStorage(NoopAppearance.storageKey) private var appearanceRaw = NoopAppearance.platformDefault.rawValue
    @State private var showWhatsNew = false

    private var appearance: NoopAppearance {
        NoopAppearance(rawValue: appearanceRaw) ?? .platformDefault
    }

    var body: some View {
        ZStack {
            RootView()
            if !onboarded {
                OnboardingWizard(onFinished: {
                    onboarded = true
                    // A brand-new user just saw the expectations in onboarding — don't also pop the
                    // changelog at them; mark them current.
                    lastSeenChangelog = AppChangelog.currentVersion
                })
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .noopAppearance(appearance)
        .animation(.easeInOut(duration: 0.35), value: onboarded)
        .sheet(isPresented: $showWhatsNew) {
            WhatsNewView(onClose: {
                lastSeenChangelog = AppChangelog.currentVersion
                showWhatsNew = false
            })
        }
        .onAppear {
            // Existing users who updated: their last-seen version is behind the current one.
            if onboarded && lastSeenChangelog != AppChangelog.currentVersion {
                showWhatsNew = true
            }
        }
        .background(ScenePhaseBridge())
    }
}

/// Routes scene-phase transitions into `AppModel` from a leaf view.
///
/// `ContentView` used to observe `AppModel` directly for this, which meant the
/// whole app shell was invalidated whenever the model published — and it
/// publishes live heart rate about once a second. This view's body is empty, so
/// observing here costs nothing.
private struct ScenePhaseBridge: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: scenePhase) { phase in
                model.handleScenePhase(phase)
            }
    }
}
