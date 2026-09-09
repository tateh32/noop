import SwiftUI
import StrandDesign

/// Smart alarm. Lives on Sleep (it is a sleep decision, not a desk automation).
///
/// Deliberately observes only `BehaviorStore`, not `AppModel` — `AppModel`
/// republishes smoothed heart rate about once a second, and observing it here
/// would re-render the Sleep screen on every beat. Arming is driven by
/// `AppModel`'s own subscription to these settings.
struct SmartAlarmCard: View {
    @EnvironmentObject private var behavior: BehaviorStore

    var body: some View {
        SettingsSection(
            icon: "alarm.fill",
            title: "Smart alarm",
            blurb: "Wake to a wrist buzz. This arms the strap's own firmware alarm, so it still fires if \(DeviceCopy.here) is asleep or NOOP is closed."
        ) {
            VStack(spacing: 0) {
                SettingsToggleRow(label: "Enable smart alarm",
                                  help: "Arms the strap to buzz at your wake time.",
                                  isOn: $behavior.smartAlarmEnabled)
                if behavior.smartAlarmEnabled {
                    SettingsRowDivider()
                    wakeAtRow
                    SettingsRowDivider()
                    windowRow
                }
            }
        }
    }

    private var wakeAtRow: some View {
        HStack {
            Text("Wake at").font(StrandFont.body).foregroundStyle(StrandPalette.textPrimary)
            Spacer()
            DatePicker("", selection: alarmTimeBinding, displayedComponents: .hourAndMinute)
                .labelsHidden().datePickerStyle(.compact)
                .accessibilityLabel("Smart alarm wake time")
        }
        .frame(minHeight: 42).padding(.vertical, 4)
    }

    private var windowRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Light-sleep window").font(StrandFont.body).foregroundStyle(StrandPalette.textPrimary)
                // Honest about scope: the firmware alarm fires at the fixed time.
                // Waking early on a detected light phase needs live overnight
                // staging, which is not wired up yet — do not imply that it is.
                Text("Still building. Your alarm fires at the time above; NOOP does not yet wake you early on a light phase.")
                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Stepper("\(behavior.smartAlarmWindow) min",
                    value: $behavior.smartAlarmWindow, in: 0...60, step: 5)
                .fixedSize()
                .accessibilityLabel("Light sleep window in minutes")
        }
        .frame(minHeight: 42).padding(.vertical, 4)
    }

    private var alarmTimeBinding: Binding<Date> {
        Binding(get: { SmartAlarmCard.date(fromMinutes: behavior.smartAlarmMinutes) },
                set: { behavior.smartAlarmMinutes = SmartAlarmCard.minutes(from: $0) })
    }

    static func date(fromMinutes m: Int) -> Date {
        Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
    }

    static func minutes(from d: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}
