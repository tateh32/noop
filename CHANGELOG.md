# Changelog

All notable changes to NOOP. NOOP is an independent, experimental project — not the WHOOP app, and
not affiliated with WHOOP. It reads a strap you own, on your own device, fully offline. Dates are
approximate; downloads are on the [Releases](https://github.com/NoopApp/noop/releases) page.

## What to expect

- **Independent, and experimental.** Treat NOOP as a capable work-in-progress rather than a finished
  product.
- **WHOOP 4.0 is the supported path.** It is tested and works end to end. WHOOP 5.0/MG is newer: live
  heart rate works today, but deeper metrics (recovery, strain, sleep) for 5/MG are still being
  figured out. NOOP always tells you what's live versus still building.
- **Your scores build over a few nights.** Live heart rate is instant; recovery, strain and sleep
  sharpen as NOOP learns your baseline. Import your WHOOP export to backfill your history instantly.
- **Everything stays on your device.** No account, no cloud, no sync.

---

## 1.3.6 — Train on Today, Explore stays put, workout log fits

iPhone layout pass for the workout log and Explore, plus a home for training
tools that were buried under More.

- **Explore** no longer pops back to More when you tap a metric. The More tab
  already has a `NavigationStack`; Explore had a second one, so the push never
  landed.
- **All Sessions** stacks on a phone instead of a ~600pt Mac table. Range pills
  scroll when they don't fit.
- **Breathe, Intervals, and Workouts** move from More onto Today as a **Train**
  section, with a **Live session** (Start / Stop), **Log a session** (after the
  fact), **Current**, and **History**.
- **Live session** records duration on the phone. Running / walking / cycling /
  hiking use **iPhone GPS** for distance and pace, and the phone’s step counter
  on foot sports. Heart rate comes from the **WHOOP strap** if it is bonded.
  There is no Apple Watch app and no live HealthKit.
- Strap-detected bouts now persist as NOOP workouts after a scored night. A
  WHOOP or Apple Health session that overlaps a detected bout still wins.
  Phone-logged sessions always stay in the log.
- Breathing Start / Test buzz and interval status / steppers wrap on a phone.

You do **not** need an Apple Watch Ultra or a Garmin. NOOP's device is the WHOOP
strap. Start a **Live session** from Today → Train (phone GPS on runs), log a
session by hand, import a WHOOP / Apple Health zip, or wear the strap overnight.

Rebuild scheme **NOOPiOS** from this branch after `xcodegen generate`.

## 1.3.5 — Today stays on today after a WHOOP import

Importing a WHOOP zip used to rewrite the Control Center date as the latest
*scored* cycle. If that cycle was 8 April (or later rows used fractional
timestamps we didn't parse), the home screen said April 8th instead of today.

- The subtitle is always **today's calendar date**.
- If the ring is an older export day, a note says so instead of pretending it's this morning.
- WHOOP timestamps with fractional seconds (`…06:14:32.379124+00:00`) import instead of being dropped.

Rebuild scheme **NOOPiOS** from this branch after `xcodegen generate`. If April 8 was wrong (the zip should include later days), Data Sources → Start over, then import a fresh zip.

## 1.3.4 — Glass look, Classic still one tap away

Liquid Glass / Health-style cards on iPhone, without throwing the original
theme away. Settings → Look switches **Glass** (frosted materials, rounded
metric numbers, indigo–cyan recovery) and **Classic** (the dark instrument
look). Classic is the default on Mac; Glass is the default on iPhone.

System materials only — not the custom forever-blur that hitching Today.

## 1.3.3 — iPhone review pass before the next sideload

A full pass over the iPhone target after 1.3.2. Three things would have bitten on device:

- **Scoring skip is per night, not all-or-nothing.** `repo.today` is the latest *scored* day (often yesterday after a WHOOP import). Skipping the whole engine meant new strap nights never got scored. Uncovered nights still score; nights that already have recovery do not.
- **iOS 16 hover compile.** `.onContinuousHover(coordinateSpace: .local)` resolves to the iOS 17 API under a current Xcode. Charts now use a 16-safe helper.
- **Zip copy is off the main thread.** Picking a WHOOP / Apple Health export no longer copies hundreds of MB on the UI actor.

Also: Live controls stack vertically, Notifications is hidden from More (Mac stub), onboarding padding and Support donate/contact wrap on a phone, scoring waits until onboarding finishes, bundle version is 1.3.3.

Rebuild scheme **NOOPiOS** from this branch after `xcodegen generate`.

## 1.3.2 — iPhone: Today is actually scrollable

1.3.1 stopped the crashes. The remaining hitch was the Mac visual budget still
running on the home screen: a forever-breathe **blur bloom** on the recovery ring,
plus-lighter halos on every sparkline, a decade of days loaded into RAM, and the
on-device scorer kicking in even after a WHOOP import.

- Recovery ring / strain gauge / sparklines drop blur, forever-breathe, and hover on iPhone.
- Trend charts skip per-point marks. Heat-strip is six months.
- Dashboard cache is 400 days, not 4000. Sleep list is 90 nights.
- Whoop sparklines come from RAM, not six extra SQLite round-trips.
- Scoring is skipped when a WHOOP import already filled recovery.

Rebuild scheme **NOOPiOS** from this branch.

## 1.3.1 — iPhone: stop the freezes and crashes

The first iPhone sideload compiled the Mac screens as-is. That is why it felt
frozen and then died: SQLite mmapped 256 MB **per open handle** (two handles),
every tab stayed alive (Today + Sleep + Trends + Live), import/scoring ran on
the main thread, and charts rebuilt years of points with a new UUID each time.

- **SQLite on iPhone** uses a 4 MB page cache, no mmap, file temp store.
- **Only the selected tab is mounted.** Leaving Live actually stops the realtime HR stream.
- **Import and sleep-staging run off the main thread.** Intelligence scores 3 nights, not 21.
- **Today / Trends query a short window** and downsample chart marks. Heat-strip is one year.
- iOS 16 no longer crashes on `.snappy` / `.numericText()` (those are availability-gated).

Sideload the **NOOPiOS** scheme again from this branch after `xcodegen generate`.

## 1.3 — iPhone app, and a WHOOP import that actually fills Today

If you sideloaded before and Today stayed empty after a WHOOP export, that was
the product — there was no iPhone target, and a successful import still pointed
Today at the in-progress cycle (blank recovery / HRV / strain).

- **iPhone app (`NOOPiOS`).** Same screens and store as the Mac app. In Xcode:
  `xcodegen generate` → scheme **NOOPiOS** → set your signing team → Run on your iPhone.
- **Import that shows up.** The WHOOP `.zip` is copied out of Files/iCloud before parse
  (in-place reads often fail on iOS). Empty trailing cycles are skipped. Today shows the
  latest *scored* day, not the open one at the end of the export.
- **Start over** on Data Sources: clears imported/computed scores so you can reimport
  cleanly. Live strap samples stay.
- **German WHOOP filenames** (`physiologische_zyklen.csv`, `Schlaf.csv`, …) are recognised.

## 1.2 — Readiness, and the start of WHOOP 5/MG

- **New: Readiness.** A "should you push today?" card on Today that synthesizes established
  sports-science signals from your own history — HRV vs your baseline (Plews/Buchheit), resting-heart-
  rate drift (Lamberts), sleeping respiratory rate, training-load balance (the acute:chronic workload
  ratio, Gabbett) and training variety (monotony, Foster) — into one headline (Primed / Balanced /
  Strained / Run down) with the drivers beneath it. Pure on-device math; not medical advice.
- **WHOOP 5/MG: live heart rate now works.** Deeper 5/MG metrics (recovery, strain, sleep) are still
  experimental and being worked on.
- **Opt-in WHOOP 5/MG protocol probes** under Settings → Experimental, for 5/MG owners who want to
  help map the protocol. Off by default; never affects WHOOP 4.0.
- **Localized exports import fully.** German (and other localized) WHOOP exports now import with real
  values, not blanks — the column headers are mapped, not just the filenames.
- **Fixes.** The WHOOP 5/MG "stuck connecting" state, and the macOS "Choose export" button.

## 1.1 — Scores live from the strap

- **On-device scoring.** Recovery, strain and sleep now compute live from the strap, not only from an
  import. They calibrate over your first few nights, like any recovery wearable.
- **Pick your strap** (WHOOP 4.0 or 5.0/MG) before connecting, so it looks for the right one.
- **Universal macOS build** that runs on both Intel and Apple Silicon.

## 1.0 — First release

- Pair directly with a WHOOP strap over Bluetooth — no WHOOP account, no cloud.
- Compute recovery, strain, HRV and sleep locally on your own device.
- Bring your history: import a WHOOP export, an Apple Health export, or Android Health Connect.
