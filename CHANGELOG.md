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

## 1.3 — Past health data: import the history, don't start the app over

Don't throw the project away if a previous import looks empty. The BLE offload and
importers stay; what's new is a clean **Start over** on Data Sources (macOS and Android)
that clears imported/computed scores so you can reimport, plus an Android fix so a WHOOP
CSV actually fills Explore / Compare / Insights / Stress (`metricSeries` was never written).

- **Android WHOOP import now writes the metric series** the explorer screens read — same keys
  as macOS (`recovery`, `hrv`, `sleep_performance`, zone minutes, derived stress, …).
- **Start over** on Data Sources: clears daily/sleep/workout/journal/Apple Health caches.
  Live strap samples stay. Confirm first; then import again.
- **Auto-detect recognises German WHOOP filenames** (`physiologische_zyklen.csv`, `Schlaf.csv`, …).

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
