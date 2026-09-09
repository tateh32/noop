import SwiftUI
import StrandDesign

// Shared settings-card idiom used by Automations, Sleep's smart alarm, and any
// future toggle screen. These were private to AutomationsView; the smart alarm
// moved to Sleep and both screens need them.

struct SettingsSection<Content: View>: View {
    let icon: String
    let title: String
    var blurb: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        StrandCard(padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: icon).foregroundStyle(StrandPalette.accent).accessibilityHidden(true)
                    Text(title).font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                }
                if let blurb {
                    Text(blurb).font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                content()
            }
        }
    }
}

struct SettingsToggleRow: View {
    let label: String
    let help: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(StrandFont.body).foregroundStyle(StrandPalette.textPrimary)
                Text(help).font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch).tint(StrandPalette.accent)
                .accessibilityLabel(label)
        }
        .frame(minHeight: 42).padding(.vertical, 4)
    }
}

struct SettingsRowDivider: View {
    var body: some View {
        Rectangle().fill(StrandPalette.hairline).frame(height: 1).padding(.vertical, 4)
    }
}
