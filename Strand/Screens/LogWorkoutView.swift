import SwiftUI
import StrandDesign
import WhoopStore
import Foundation

// MARK: - Log a session (phone, no watch)

/// Manual workout entry. WHOOP export / Apple Health import / strap detection still
/// fill the log on their own; this is for the session you just finished that never
/// landed anywhere else. Nothing here talks to an Apple Watch or Garmin.

struct LogWorkoutView: View {
    @EnvironmentObject var repo: Repository
    @Environment(\.dismiss) private var dismiss

    var onSaved: (() -> Void)? = nil

    @State private var sport: String = WorkoutSport.running.rawValue
    /// Defaults to 45 minutes ago — "I just finished."
    @State private var start: Date = Date().addingTimeInterval(-45 * 60)
    @State private var durationMin: Int = 45
    @State private var energyText: String = ""
    @State private var hrText: String = ""
    @State private var notes: String = ""
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        ScreenScaffold(title: "Log a session",
                       subtitle: "On this phone. No Apple Watch or Garmin required.") {
            DataPendingNote(
                title: "You type it. The strap does not have to.",
                message: "Pick the sport, when it started, and how long. Calories and average HR are optional. Import a WHOOP zip later if you want the strap’s own history too.",
                symbol: "figure.run")

            detailsCard
            extrasCard
            saveButton

            if let error {
                Text(error)
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.statusCritical)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var detailsCard: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: 14) {
                fieldLabel("Sport")
                Picker("Sport", selection: $sport) {
                    ForEach(WorkoutSport.allCases) { s in
                        Text(s.rawValue).tag(s.rawValue)
                    }
                }
                #if os(iOS)
                .pickerStyle(.menu)
                #endif
                .accessibilityLabel("Sport")

                Divider().overlay(StrandPalette.hairline)

                fieldLabel("Started")
                DatePicker("Started", selection: $start, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .accessibilityLabel("Workout start")

                Divider().overlay(StrandPalette.hairline)

                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Duration").font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                        Text("5–300 min")
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textTertiary)
                    }
                    Spacer(minLength: 8)
                    Text("\(durationMin) min")
                        .font(StrandFont.number(24))
                        .foregroundStyle(StrandPalette.accent)
                }
                Stepper("Duration", value: $durationMin, in: 5...300, step: 5)
                    .labelsHidden()
                    .accessibilityLabel("Duration \(durationMin) minutes")
            }
        }
    }

    private var extrasCard: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: 14) {
                fieldLabel("Calories (optional)")
                TextField("kcal", text: $energyText)
                    .textFieldStyle(.roundedBorder)
                    .font(StrandFont.body)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .accessibilityLabel("Calories")

                Divider().overlay(StrandPalette.hairline)

                fieldLabel("Average heart rate (optional)")
                TextField("bpm", text: $hrText)
                    .textFieldStyle(.roundedBorder)
                    .font(StrandFont.body)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                    .accessibilityLabel("Average heart rate")

                Divider().overlay(StrandPalette.hairline)

                fieldLabel("Notes (optional)")
                TextField("How it felt", text: $notes)
                    .textFieldStyle(.roundedBorder)
                    .font(StrandFont.body)
                    .accessibilityLabel("Notes")
            }
        }
    }

    private var saveButton: some View {
        Button {
            Task { await save() }
        } label: {
            Label(saving ? "Saving…" : "Save session",
                  systemImage: saving ? "hourglass" : "checkmark.circle.fill")
                .font(StrandFont.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .tint(StrandPalette.accent)
        .disabled(saving)
        .accessibilityLabel("Save workout session")
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title.uppercased()).strandOverline()
    }

    @MainActor
    private func save() async {
        error = nil
        let kcalText = energyText.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        let kcal: Double?
        if kcalText.isEmpty {
            kcal = nil
        } else if let v = Double(kcalText), v >= 0, v.isFinite {
            kcal = v
        } else {
            error = "Calories need a number, or leave that field blank."
            return
        }

        let hrTextTrimmed = hrText.trimmingCharacters(in: .whitespacesAndNewlines)
        let hr: Int?
        if hrTextTrimmed.isEmpty {
            hr = nil
        } else if let v = Int(hrTextTrimmed), (1..<250).contains(v) {
            hr = v
        } else {
            error = "Average HR needs a whole number, or leave that field blank."
            return
        }

        saving = true
        defer { saving = false }

        let startTs = Int(start.timeIntervalSince1970)
        let durationS = Double(durationMin) * 60
        let endTs = startTs + Int(durationS)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let row = WorkoutRow(
            startTs: startTs, endTs: endTs, sport: sport, source: "logged",
            durationS: durationS, energyKcal: kcal, avgHr: hr, maxHr: nil,
            strain: nil, distanceM: nil, zonesJSON: nil,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes)
        let ok = await repo.logWorkout(row)
        guard ok else {
            error = "Could not save this session on the phone. Try again in a moment."
            return
        }
        onSaved?()
        dismiss()
    }
}

enum WorkoutSport: String, CaseIterable, Identifiable {
    case running = "Running"
    case walking = "Walking"
    case cycling = "Cycling"
    case strength = "Strength Training"
    case hiit = "HIIT"
    case yoga = "Yoga"
    case swimming = "Swimming"
    case hiking = "Hiking"
    case other = "Workout"
    var id: String { rawValue }
}

/// Full-width door into `LogWorkoutView` — used on Today → Train and the workout log.
struct LogWorkoutEntryLink: View {
    var caption: String = "Sport, start, duration — no watch needed"
    var onSaved: (() -> Void)? = nil

    var body: some View {
        NavigationLink {
            LogWorkoutView(onSaved: onSaved)
        } label: {
            NoopCard {
                HStack(spacing: 12) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(StrandPalette.accent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Log a session")
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
        .accessibilityLabel("Log a workout session")
    }
}
