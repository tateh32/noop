import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore
import Foundation

// MARK: - Control Center (the home dashboard) — HomeDensity rewrite
//
// The owner's complaint was "cards then random space". This rebuild is a tight,
// GAPLESS dashboard grid: one column of uniform sections, every gap == NoopMetrics.gap,
// every section break == NoopMetrics.sectionGap, equal margins from ScreenScaffold.
//
// Composition (top → bottom):
//   (a) HERO  — full-width HStack that fills the width EQUALLY: RecoveryRing (left card)
//               + InsightCard "Today's Synthesis" (right card). No lone card, no gap.
//   (b) TRAIN (iPhone, top of Today) — Live session, Log a session, Breathe, Intervals, History, Current.
//   (c) METRICS — one adaptive LazyVGrid of fixed-104pt StatTiles (Recovery, Strain,
//               Sleep, HRV, RHR, SpO2, Respiratory, Steps, Weight, Calories) each with
//               a 14-day sparkline so the grid tiles perfectly with no empty cells.
//   (d) LAST WORKOUTS — the SAME adaptive grid of fixed-104pt workout StatTiles.
//   (e) DATA SOURCES — one full-width NoopCard footer of SourceBadges + counts.
//
// Sparse series (weight) fall back to ALL history so a tile never shows an empty
// state when data exists. Only locked StrandDesign components are used.

struct TodayView: View {
    @EnvironmentObject var repo: Repository
    @Environment(\.noopAppearance) private var appearance

    // 14-day sparkline series, keyed by metric key. Loaded once in .task.
    @State private var sparks: [String: [Double]] = [:]
    @State private var workouts: [WorkoutRow] = []
    @State private var appleDays: [AppleDaily] = []
    @State private var readiness: ReadinessEngine.Readiness?

    // Support sheet (donate + contact) — always reachable from the home toolbar.
    @State private var showingSupport = false

    // THE single grid definition — every tile group reuses it so margins line up.
    private let grid = [GridItem(.adaptive(minimum: 168), spacing: NoopMetrics.gap)]

    var body: some View {
        ScreenScaffold(title: "Control Center", subtitle: dateLine) {
            Group {
                #if os(iOS)
                LazyVStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                    todaySections
                }
                #else
                VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                    todaySections
                }
                #endif
            }
        }
        .task(id: repo.today?.day) { await loadAll() }
        .toolbar {
            ToolbarItem {
                Button { showingSupport = true } label: {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(StrandPalette.metricRose)
                        .attentionWiggle(period: 4)
                }
                .help("Support NOOP — donate or get in touch")
                .accessibilityLabel("Support NOOP — donate or get in touch")
            }
            #if os(iOS)
            ToolbarItem(placement: .navigationBarLeading) {
                NavigationLink {
                    LiveSessionView { Task { await reloadWorkouts() } }
                } label: {
                    Image(systemName: "play.circle.fill")
                }
                .accessibilityLabel("Start live session")
            }
            #endif
        }
        #if os(iOS)
        .sheet(isPresented: $showingSupport) {
            NavigationStack {
                SupportView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingSupport = false }
                        }
                    }
            }
        }
        #else
        .overlay {
            if showingSupport {
                SupportModalOverlay(isPresented: $showingSupport)
            }
        }
        .animation(.easeOut(duration: 0.18), value: showingSupport)
        #endif
    }

    @ViewBuilder
    private var todaySections: some View {
        HealthAlertBanner()
        #if os(iOS)
        startLiveSessionButton
        trainSection
        #endif
        if repo.days.isEmpty {
            DataPendingNote(
                title: "Live now. Your scores are building.",
                message: "Your live heart rate is working from the strap, and recovery, strain and sleep build from it over your next few nights of wear, sharpening as it learns your baseline. Want your full history instantly? Import your WHOOP export in Data Sources and it backfills in about a minute."
            )
        } else if repo.today?.recovery == nil && repo.today?.avgHrv == nil && repo.today?.strain == nil {
            DataPendingNote(
                title: "Days are in. Scores are still blank.",
                message: "NOOP stored \(repo.days.count) days but none have recovery, HRV or strain yet. On Data Sources, tap Start over, then import the .zip from app.whoop.com → Data Management."
            )
        } else if let stale = staleScoreNote {
            DataPendingNote(title: stale.title, message: stale.message, symbol: "calendar")
        }
        heroSection
        readinessSection
        metricsSection
        workoutsSection
        sourcesSection
    }

    // MARK: Readiness — on-device training-readiness synthesis (HRV / resting-HR / load).

    @ViewBuilder
    private var readinessSection: some View {
        if let r = readiness, r.level != .insufficient {
            VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                SectionHeader("Readiness", overline: "Should you push today?")
                NoopCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            Circle().fill(readinessColor(r.level)).frame(width: 10, height: 10)
                            Text(r.headline).font(StrandFont.headline)
                                .foregroundStyle(StrandPalette.textPrimary)
                            Spacer()
                            if let acwr = r.acwr {
                                Text("load \(String(format: "%.2f", acwr))")
                                    .font(StrandFont.captionNumber)
                                    .foregroundStyle(StrandPalette.textTertiary)
                                    .help("Acute (7-day) vs chronic (28-day) training load. 0.8–1.3 is the sweet spot.")
                            }
                        }
                        Text(r.summary).font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if !r.signals.isEmpty {
                            Divider().overlay(StrandPalette.hairline)
                            ForEach(r.signals, id: \.key) { s in
                                HStack(alignment: .top, spacing: 8) {
                                    Circle().fill(flagColor(s.flag)).frame(width: 7, height: 7)
                                        .padding(.top, 5)
                                    Text(s.label).font(StrandFont.caption)
                                        .foregroundStyle(StrandPalette.textSecondary)
                                        .frame(width: 104, alignment: .leading)
                                    Text(s.detail).font(StrandFont.caption)
                                        .foregroundStyle(StrandPalette.textTertiary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func readinessColor(_ l: ReadinessEngine.Level) -> Color {
        switch l {
        case .primed:       return StrandPalette.accent
        case .balanced:     return StrandPalette.statusPositive
        case .strained:     return StrandPalette.statusWarning
        case .rundown:      return StrandPalette.metricRose
        case .insufficient: return StrandPalette.textTertiary
        }
    }

    private func flagColor(_ f: ReadinessEngine.Flag) -> Color {
        switch f {
        case .good:    return StrandPalette.accent
        case .neutral: return StrandPalette.textTertiary
        case .watch:   return StrandPalette.statusWarning
        case .bad:     return StrandPalette.metricRose
        }
    }

    // MARK: (a) HERO — RecoveryRing + Synthesis, filling the width equally.

    @ViewBuilder
    private var heroSection: some View {
        let d = repo.today
        let score = d?.recovery
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            SectionHeader("Today’s Synthesis", overline: "At a glance",
                          trailing: staleScoreCaption ?? greetingWord)
            HStack(alignment: .top, spacing: NoopMetrics.gap) {
                NoopCard {
                    RecoveryRing(
                        score: score ?? 0,
                        supporting: ringSupporting(d),
                        diameter: PhoneBudget.isPhone ? 200 : 168
                    )
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, alignment: .center)

                if !PhoneBudget.isPhone {
                    InsightCard(
                        category: "Recovery",
                        status: synthesisWord(score),
                        detail: synthesisDetail(d),
                        statusColor: score.map { StrandPalette.recoveryColor($0, appearance: appearance) } ?? StrandPalette.textTertiary
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if PhoneBudget.isPhone {
                InsightCard(
                    category: "Recovery",
                    status: synthesisWord(score),
                    detail: synthesisDetail(d),
                    statusColor: score.map { StrandPalette.recoveryColor($0, appearance: appearance) } ?? StrandPalette.textTertiary
                )
            }
        }
    }

    // MARK: (b) METRICS — one uniform grid of 104pt StatTiles, every cell filled.

    @ViewBuilder
    private var metricsSection: some View {
        let d = repo.today
        let aLatest = appleDays.last
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            SectionHeader("Key Metrics", overline: "Today", trailing: "14-day trend")
            LazyVGrid(columns: grid, alignment: .leading, spacing: NoopMetrics.gap) {
                StatTile(
                    label: "Recovery",
                    value: d?.recovery.map { "\(Int($0.rounded()))%" } ?? "—",
                    caption: d?.recovery.map { StrandPalette.recoveryState($0).capitalized },
                    accent: d?.recovery.map { StrandPalette.recoveryColor($0, appearance: appearance) } ?? StrandPalette.textPrimary,
                    sparkline: sparks["recovery"],
                    sparkColor: StrandPalette.accent
                )
                StatTile(
                    label: "Day Strain",
                    value: d?.strain.map { String(format: "%.1f", $0) } ?? "—",
                    caption: "of 21",
                    accent: d?.strain.map { StrandPalette.strainColor($0) } ?? StrandPalette.textPrimary,
                    sparkline: sparks["strain"],
                    sparkColor: StrandPalette.strain066
                )
                StatTile(
                    label: "Sleep",
                    value: sleepValue(d),
                    caption: d?.efficiency.map { String(format: "%.0f%% eff", $0) },
                    accent: StrandPalette.textPrimary,
                    sparkline: sparks["sleep_total_min"],
                    sparkColor: StrandPalette.metricPurple
                )
                StatTile(
                    label: "HRV",
                    value: d?.avgHrv.map { "\(Int($0.rounded()))" } ?? "—",
                    caption: "ms",
                    accent: StrandPalette.metricPurple,
                    sparkline: sparks["hrv"],
                    sparkColor: StrandPalette.metricPurple
                )
                StatTile(
                    label: "Resting HR",
                    value: d?.restingHr.map { "\($0)" } ?? "—",
                    caption: "bpm",
                    accent: StrandPalette.metricRose,
                    sparkline: sparks["rhr"],
                    sparkColor: StrandPalette.metricRose
                )
                StatTile(
                    label: "Blood Oxygen",
                    value: d?.spo2Pct.map { String(format: "%.0f%%", $0) } ?? "—",
                    caption: "SpO₂",
                    accent: StrandPalette.metricCyan,
                    sparkline: sparks["spo2"],
                    sparkColor: StrandPalette.metricCyan
                )
                StatTile(
                    label: "Respiratory",
                    value: d?.respRateBpm.map { String(format: "%.1f", $0) } ?? latestString("resp_rate", decimals: 1),
                    caption: "rpm",
                    accent: StrandPalette.accent,
                    sparkline: sparks["resp_rate"],
                    sparkColor: StrandPalette.accent
                )
                StatTile(
                    label: "Steps",
                    value: aLatest?.steps.map { intString(Double($0)) } ?? latestString("steps", decimals: 0),
                    caption: "today",
                    accent: StrandPalette.metricCyan,
                    sparkline: sparks["steps"],
                    sparkColor: StrandPalette.metricCyan
                )
                StatTile(
                    label: "Weight",
                    value: aLatest?.weightKg.map { String(format: "%.1f kg", $0) } ?? latestString("weight", decimals: 1, unit: "kg"),
                    caption: "latest",
                    accent: StrandPalette.accent,
                    sparkline: sparks["weight"],
                    sparkColor: StrandPalette.accent
                )
                StatTile(
                    label: "Calories",
                    value: caloriesValue(aLatest),
                    caption: "active",
                    accent: StrandPalette.metricAmber,
                    sparkline: sparks["active_kcal"],
                    sparkColor: StrandPalette.metricAmber
                )
            }
        }
    }

    // MARK: Train — Breathe / Intervals / Workouts / Current (iPhone).
    // Mac keeps these in the sidebar; More on iPhone was too deep and too cramped.

    #if os(iOS)
    private var startLiveSessionButton: some View {
        NavigationLink {
            LiveSessionView { Task { await reloadWorkouts() } }
        } label: {
            Label("Start live session", systemImage: "play.fill")
                .font(StrandFont.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(StrandPalette.accent)
        .accessibilityLabel("Start live session")
    }

    @ViewBuilder
    private var trainSection: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            SectionHeader("Train", overline: "Work",
                          trailing: workoutsToday.isEmpty ? "No session today" : "\(workoutsToday.count) today")
            LiveSessionEntryLink {
                Task { await reloadWorkouts() }
            }
            LogWorkoutEntryLink {
                Task { await reloadWorkouts() }
            }
            LazyVGrid(columns: grid, alignment: .leading, spacing: NoopMetrics.gap) {
                NavigationLink {
                    BreathingView()
                } label: {
                    StatTile(label: "Breathe", value: "Session", caption: "Haptic pace",
                             accent: StrandPalette.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Breathe session")

                NavigationLink {
                    IntervalTimerView()
                } label: {
                    StatTile(label: "Intervals", value: "Timer", caption: "Strap buzzes",
                             accent: StrandPalette.metricCyan)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Interval timer")

                NavigationLink {
                    WorkoutsView()
                } label: {
                    StatTile(label: "History", value: workouts.isEmpty ? "—" : "\(workouts.count)",
                             caption: "All sessions",
                             accent: StrandPalette.textPrimary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("All workout sessions")

                currentSessionLink
            }
        }
    }

    private var currentSessionLink: some View {
        let todayRows = workoutsToday
        let latest = todayRows.first ?? workouts.first
        let label = todayRows.isEmpty ? "Latest" : "Current"
        let value = latest.map(workoutDuration) ?? "—"
        let caption: String = {
            guard let w = latest else { return "No sessions yet" }
            return todayRows.isEmpty ? workoutCaption(w) : w.sport
        }()
        return NavigationLink {
            CurrentWorkoutsView()
        } label: {
            StatTile(label: label, value: value, caption: caption,
                     accent: StrandPalette.strainColor(latest?.strain ?? 8),
                     delta: todayRows.isEmpty ? nil : "today",
                     deltaColor: StrandPalette.metricAmber)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) workout")
    }
    #endif

    // MARK: (c) LAST WORKOUTS — SAME grid, uniform 104pt workout tiles.

    @ViewBuilder
    private var workoutsSection: some View {
        if !workouts.isEmpty {
            VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                SectionHeader("Last Workouts", overline: "Activity",
                              trailing: "\(workouts.count) total")
                LazyVGrid(columns: grid, alignment: .leading, spacing: NoopMetrics.gap) {
                    ForEach(Array(workouts.prefix(6).enumerated()), id: \.offset) { _, w in
                        StatTile(
                            label: w.sport,
                            value: workoutDuration(w),
                            caption: workoutCaption(w),
                            accent: StrandPalette.strainColor(w.strain ?? 0),
                            delta: w.energyKcal.map { "\(Int($0.rounded())) kcal" },
                            deltaColor: StrandPalette.metricAmber
                        )
                    }
                }
            }
        }
    }

    // MARK: (d) DATA SOURCES — one full-width footer card.

    @ViewBuilder
    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            SectionHeader("Data Sources", overline: "Provenance")
            NoopCard {
                VStack(alignment: .leading, spacing: 12) {
                    sourceRow(
                        badge: "Whoop",
                        tint: StrandPalette.accent,
                        present: !repo.days.isEmpty,
                        detail: "\(repo.days.count) days · \(repo.sleeps.count) sleeps"
                    )
                    Divider().overlay(StrandPalette.hairline)
                    sourceRow(
                        badge: "Apple Health",
                        tint: StrandPalette.metricCyan,
                        present: !appleDays.isEmpty,
                        detail: "\(appleDays.count) days · \(workouts.filter { $0.source.lowercased().contains("apple") }.count) workouts"
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func sourceRow(badge: String, tint: Color, present: Bool, detail: String) -> some View {
        HStack(spacing: 10) {
            SourceBadge(badge, tint: present ? tint : StrandPalette.textTertiary)
            Spacer()
            Text(present ? detail : "Not connected")
                .font(StrandFont.captionNumber)
                .foregroundStyle(present ? StrandPalette.textSecondary : StrandPalette.textTertiary)
        }
    }

    // MARK: - Loading

    private func loadAll() async {
        readiness = ReadinessEngine.evaluate(days: repo.days)

        // Whoop tiles: spark from the days already in RAM. Skip 6 metricSeries round-trips.
        let tail = repo.days.suffix(14)
        sparks["recovery"]        = tail.compactMap(\.recovery)
        sparks["strain"]          = tail.compactMap(\.strain)
        sparks["sleep_total_min"] = tail.compactMap(\.totalSleepMin)
        sparks["hrv"]             = tail.compactMap(\.avgHrv)
        sparks["rhr"]             = tail.compactMap { $0.restingHr.map(Double.init) }
        sparks["spo2"]            = tail.compactMap(\.spo2Pct)

        sparks["resp_rate"]   = await sparkValues("resp_rate", source: "apple-health", window: 14)
        sparks["steps"]       = await sparkValues("steps", source: "apple-health", window: 14)
        sparks["weight"]      = await sparkValues("weight", source: "apple-health", window: 90)
        sparks["active_kcal"] = await sparkValues("active_kcal", source: "apple-health", window: 14)

        workouts = await repo.workoutRows(days: PhoneBudget.workoutQueryDays)
        appleDays = await repo.appleDailyRows(days: PhoneBudget.sparkQueryDays)
    }

    #if os(iOS)
    private func reloadWorkouts() async {
        workouts = await repo.workoutRows(days: PhoneBudget.workoutQueryDays)
    }
    #endif

    /// Trailing-window values for a metric, with the sparse-data fallback:
    /// if the trailing window has <2 points, fall back to a longer (still capped)
    /// history so sparse series (weight) still render a value + line.
    private func sparkValues(_ key: String, source: String, window: Int) async -> [Double] {
        let all = await repo.series(key: key, source: source, days: PhoneBudget.sparkQueryDays)
        guard !all.isEmpty else { return [] }
        let windowed = trailingWindow(all, days: window)
        let chosen = windowed.count >= 2 ? windowed : all
        return chosen.map { $0.value }
    }

    /// Keep only points within `days` of the most recent point (parsing yyyy-MM-dd in UTC).
    private func trailingWindow(_ points: [(day: String, value: Double)], days: Int) -> [(day: String, value: Double)] {
        guard let lastDay = points.last?.day, let lastDate = Self.dayParser.date(from: lastDay) else { return points }
        let cutoff = lastDate.addingTimeInterval(-Double(days) * 86_400)
        return points.filter { p in
            guard let dt = Self.dayParser.date(from: p.day) else { return false }
            return dt >= cutoff
        }
    }

    /// Latest value of a loaded sparkline series, formatted — for tiles whose hero
    /// can't be read off `appleDailyRows` (e.g. respiratory from apple-health).
    private func latestString(_ key: String, decimals: Int, unit: String = "") -> String {
        guard let last = sparks[key]?.last else { return "—" }
        let n = decimals == 0 ? intString(last) : String(format: "%.\(decimals)f", last)
        return unit.isEmpty ? n : "\(n) \(unit)"
    }

    // MARK: - Derived text

    /// Greeting word used as the section's trailing label (no lone text block).
    private var greetingWord: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case ..<12:   return "Good morning"
        case 12..<17: return "Good afternoon"
        default:      return "Good evening"
        }
    }

    private var dateLine: String {
        let f = DateFormatter()
        f.locale = .current
        f.timeZone = .current
        f.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return f.string(from: Date())
    }

    /// Latest imported/scored day is not calendar today — say so instead of
    /// relabeling the whole home screen as that older date.
    private var staleScoreCaption: String? {
        guard let day = repo.today?.day, !Repository.isCalendarToday(day) else { return nil }
        return Repository.prettyDay(day) ?? day
    }

    private var staleScoreNote: (title: String, message: String)? {
        guard let day = repo.today?.day, !Repository.isCalendarToday(day) else { return nil }
        let label = Repository.prettyDay(day) ?? day
        if Repository.calendarDaysAgo(day) == 1 {
            return (
                "Showing yesterday",
                "Today’s WHOOP cycle is still open, so it has no recovery yet. Yesterday’s score is on the ring."
            )
        }
        return (
            "Latest scored day is \(label)",
            "That’s the newest complete day in your WHOOP export. The date above is today. Live heart rate is now; tonight’s recovery lands after you sleep with the strap connected to NOOP. If the export should include later days, tap Start over in Data Sources and import a fresh zip from app.whoop.com → Data Management."
        )
    }

    /// A short recovery state word for the synthesis hero.
    private func synthesisWord(_ score: Double?) -> String {
        guard let s = score else { return "No Data" }
        switch s {
        case ..<25:  return "Depleted"
        case ..<50:  return "Low"
        case ..<70:  return "Steady"
        case ..<88:  return "Primed"
        default:     return "Peak"
        }
    }

    /// Plain-English synthesis of recovery + sleep.
    private func synthesisDetail(_ d: DailyMetric?) -> String {
        guard let d, let rec = d.recovery else {
            return "No metrics yet. Import your Whoop export or wear the strap to begin."
        }
        let recPart: String
        switch rec {
        case ..<50:  recPart = "Recovery is low"
        case ..<70:  recPart = "Recovery is steady"
        default:     recPart = "Recovery is strong"
        }
        let sleepPart: String
        if let mins = d.totalSleepMin {
            let h = mins / 60.0
            sleepPart = h >= 7 ? " and sleep was consistent" : " but sleep ran short"
        } else {
            sleepPart = ""
        }
        return recPart + sleepPart + "."
    }

    private func ringSupporting(_ d: DailyMetric?) -> String {
        let hrv = d?.avgHrv.map { "\(Int($0.rounded())) ms" } ?? "— ms"
        let rhr = d?.restingHr.map { "\($0)" } ?? "—"
        return "HRV \(hrv) · RHR \(rhr)"
    }

    private func sleepValue(_ d: DailyMetric?) -> String {
        guard let m = d?.totalSleepMin else { return "—" }
        let h = Int(m) / 60, mm = Int(m) % 60
        return "\(h)h \(mm)m"
    }

    /// Active calories (Apple) for the latest day, falling back to the sparkline tail.
    private func caloriesValue(_ a: AppleDaily?) -> String {
        if let kcal = a?.activeKcal { return intString(kcal) }
        return latestString("active_kcal", decimals: 0)
    }

    #if os(iOS)
    private var workoutsToday: [WorkoutRow] {
        let lo = Int(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)
        return workouts.filter { $0.startTs >= lo }
    }
    #endif

    private func workoutDuration(_ w: WorkoutRow) -> String {
        let secs = w.durationS ?? Double(max(w.endTs - w.startTs, 0))
        let mins = Int((secs / 60).rounded())
        if mins >= 60 { return "\(mins / 60)h \(mins % 60)m" }
        return "\(mins)m"
    }

    private func workoutCaption(_ w: WorkoutRow) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "d MMM"
        let date = f.string(from: Date(timeIntervalSince1970: TimeInterval(w.startTs)))
        if let hr = w.avgHr { return "\(date) · \(hr) bpm" }
        return date
    }

    /// Thousands-grouped integer string (steps / calories).
    private func intString(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "\(Int(v.rounded()))"
    }

    // MARK: - Date parsing (yyyy-MM-dd, en_US_POSIX, UTC)

    static let dayParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

// MARK: - Preview

#if DEBUG
#Preview("Control Center") {
    let repo = Repository(deviceId: "preview")
    let cal = Calendar(identifier: .gregorian)
    let today = cal.startOfDay(for: Date())
    var sample: [DailyMetric] = []
    for i in stride(from: 39, through: 0, by: -1) {
        let date = cal.date(byAdding: .day, value: -i, to: today)!
        let day = Repository.dayString(date)
        let phase = Double(i)
        let rec = 48 + 34 * sin(phase / 5.0) + Double((i * 7) % 11)
        let strain = 8 + 7 * abs(sin(phase / 4.0))
        let total = 380 + 70 * sin(phase / 6.0)
        sample.append(DailyMetric(
            day: day, totalSleepMin: total, efficiency: 88 + 6 * sin(phase / 3.0),
            deepMin: 95, remMin: 110, lightMin: total - 200, disturbances: 4,
            restingHr: 50 + (i % 6), avgHrv: 58 + 16 * sin(phase / 4.0),
            recovery: min(max(rec, 8), 99), strain: strain, exerciseCount: i % 3,
            spo2Pct: 96, skinTempDevC: 33.4, respRateBpm: 14.6
        ))
    }
    repo.days = sample
    repo.loaded = true

    return TodayView()
        .environmentObject(repo)
        .frame(width: 920, height: 940)
        .preferredColorScheme(.dark)
}
#endif
