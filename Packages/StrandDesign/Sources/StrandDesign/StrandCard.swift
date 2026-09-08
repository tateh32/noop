import SwiftUI

// MARK: - StrandCard (§9.4 Cards)
//
// Classic: surface.raised, 16pt radius, hairline, hover lift on Mac.
// Glass: ultraThinMaterial, larger continuous radius, specular edge.

public struct StrandCard<Content: View>: View {

    public var padding: CGFloat
    public var cornerRadius: CGFloat?
    @ViewBuilder public var content: () -> Content
    @Environment(\.noopAppearance) private var appearance

    public init(
        padding: CGFloat = 16,
        cornerRadius: CGFloat? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.content = content
    }

    private var radius: CGFloat { cornerRadius ?? appearance.cardRadius }

    public var body: some View {
        let r = radius
        if appearance.isGlass {
            content()
                .padding(padding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: r, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay { NoopGlassStroke(cornerRadius: r) }
                .shadow(color: Color.black.opacity(0.22), radius: 16, y: 8)
        } else {
            content()
                .padding(padding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(StrandPalette.surfaceRaised, in: RoundedRectangle(cornerRadius: r, style: .continuous))
                .strandCardHover(cornerRadius: r)
        }
    }
}

// MARK: - Hover lift modifier

/// The mandated hover behavior: shadow-md + translateY(-1px) and a hairline →
/// hairline.strong border on hover. Apply to any card-like surface.
public struct StrandCardHover: ViewModifier {
    public var cornerRadius: CGFloat
    @State private var hovering = false

    public init(cornerRadius: CGFloat = 16) {
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(hovering ? StrandPalette.hairlineStrong : StrandPalette.hairline, lineWidth: 1)
            )
            .shadow(
                color: Color.black.opacity(hovering ? 0.45 : 0.0),
                radius: hovering ? 14 : 0,
                x: 0,
                y: hovering ? 8 : 0
            )
            .offset(y: hovering ? -1 : 0)
            .animation(StrandMotion.interactive, value: hovering)
            .onHover { hovering = $0 }
    }
}

public extension View {
    /// Apply the Strand card hover lift (shadow + -1px translate + border emphasis).
    func strandCardHover(cornerRadius: CGFloat = 16) -> some View {
        modifier(StrandCardHover(cornerRadius: cornerRadius))
    }
}

#if DEBUG
#Preview("StrandCard") {
    VStack(spacing: 16) {
        StrandCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Sleep performance").strandOverline()
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("87").font(StrandFont.number(34)).foregroundStyle(StrandPalette.textPrimary)
                    Text("%").font(StrandFont.headline).foregroundStyle(StrandPalette.textTertiary)
                }
                Text("7h 42m asleep · 92% efficiency")
                    .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
            }
        }
        StrandCard {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Resting HR").strandOverline()
                    Text("51 bpm").font(StrandFont.title2).foregroundStyle(StrandPalette.textPrimary)
                }
                Spacer()
                Sparkline(values: (0..<30).map { i -> Double in 50 + 4 * sin(Double(i) / 5) })
                    .frame(width: 120, height: 40)
            }
        }
        Text("Hover the cards to see the lift.")
            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
    }
    .padding(28)
    .frame(width: 420, height: 360)
    .background(StrandPalette.surfaceBase)
    .preferredColorScheme(.dark)
}
#endif
