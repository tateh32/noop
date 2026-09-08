import SwiftUI

/// Strand design system: palette, typography, motion, and signature components
/// (Recovery Ring, Strain Gauge, Hypnogram, Trend/Sparkline charts, Year heat
/// strip, cards, status chips). Dark-only, instrument-grade. See spec §9.
///
/// Token entry points:
/// - `StrandPalette` — every semantic color token (§9.1), recovery/strain sampling.
/// - `StrandFont` — the full type scale with tabular digits (§9.2).
/// - `StrandMotion` — spring presets + durations (§9.6).
public enum StrandDesign {
    public static let version = "0.1.0"
}

/// Visual extras that were designed for a Mac GPU.
///
/// On iPhone these keep compositing even when the user is doing nothing: a
/// forever-breathe blur on the recovery ring, plus-lighter sparkline halos,
/// hover tooltips, and a PointMark per trend sample.
public enum StrandPerf {
    public static var reducedEffects: Bool {
        #if os(iOS)
        true
        #else
        false
        #endif
    }
}
