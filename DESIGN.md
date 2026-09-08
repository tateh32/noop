# DESIGN.md — iOS Health App Design System

NOOP ships two looks. **Classic** is the original dark instrument theme.
**Glass** follows Apple’s Liquid Glass / Health visual language. Switch them
in Settings → Look. Classic is never deleted.

This file is the Glass contract. Classic tokens live in `StrandPalette`.

## 1. Vision

- Depth over flatness: layered materials, not solid gray cards.
- Vibrancy: health data glows slightly against a dark frosted field.
- Continuous curves: always `RoundedRectangle(..., style: .continuous)`.
- Restraint: system materials (`.ultraThinMaterial`), not custom forever-blur.
  Custom `.blur()` + `.plusLighter` + breathe loops hitch iPhone. Do not
  reintroduce those. Ambient glow is a colored *shadow*.

## 2. Typography

- System SF Pro. Rounded + `monospacedDigit()` for primary metric numbers.
- Titles: `.primary`. Units (bpm, kcal): `.secondary` / `.tertiary`.
- Never invent a new gray for text when Glass is on — hierarchical styles
  pick up vibrancy on materials.

## 3. Health color tokens (Glass)

- Cardio / HR: `Color.pink` → `Color.red`
- Activity / energy: `Color.orange` → `Color.red`
- Sleep / recovery: `Color.indigo` → `Color.cyan`
- Mindfulness / breath: `Color.mint` → `Color.teal`

Ambient glow on a hero ring or chart:

```swift
.shadow(color: .cyan.opacity(0.3), radius: 20, x: 0, y: 10)
```

## 4. Materials

**Layer 0 — background:** near-black mesh (static radials, not animated).

**Layer 1 — cards:** `.ultraThinMaterial`, ~28–32pt continuous radius, 1pt
specular stroke (white 0.4 → clear → white 0.1).

**Layer 2 — tab bar / floating controls:** `.regularMaterial` / `.ultraThinMaterial`
in a capsule. Tab bar uses `toolbarBackground(.ultraThinMaterial, for: .tabBar)`.

## 5. Visualizations

- Rings: `Circle`/`Arc` + `AngularGradient`, `lineCap: .round`.
- Historical series: Swift Charts where the screen already uses Charts.
  Hide axes when they add nothing. Smooth interpolation. Area fill fades to clear.

## 6. Motion & haptics

- Springs: `response: 0.4, dampingFraction: 0.7` for Glass interactions.
- Theme change and completed goals: `UIImpactFeedbackGenerator(style: .soft)` on iOS.

## 7. Guardrails

1. Never `.cornerRadius()`. Always `clipShape(RoundedRectangle(..., style: .continuous))`.
2. Never solid gray cards in Glass. Use `.ultraThinMaterial` / `.thinMaterial`.
3. Glass is dark. Keep `.preferredColorScheme(.dark)` so white text on glass contrasts.
4. SF Symbols with `.symbolRenderingMode(.hierarchical)` on chrome icons.
5. Classic must remain pixel-true when Settings → Look → Classic is selected.
