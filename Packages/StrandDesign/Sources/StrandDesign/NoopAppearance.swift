import SwiftUI

/// The two shipped looks. Classic is the original Strand instrument theme
/// (`StrandPalette` hex tokens). Glass is the Liquid Glass / Health look.
/// Persist the raw value under `NoopAppearance.storageKey`.
public enum NoopAppearance: String, CaseIterable, Identifiable, Sendable {
    case classic
    case glass

    public var id: String { rawValue }

    public static let storageKey = "noop.appearance"

    /// First-launch default: Glass on iPhone, Classic on Mac.
    public static var platformDefault: NoopAppearance {
        #if os(iOS)
        .glass
        #else
        .classic
        #endif
    }

    public var label: String {
        switch self {
        case .classic: return "Classic"
        case .glass: return "Glass"
        }
    }

    public var detail: String {
        switch self {
        case .classic: return "The original dark instrument look."
        case .glass: return "Frosted cards, rounded numbers, Health-style glow."
        }
    }

    public var isGlass: Bool { self == .glass }

    public var cardRadius: CGFloat { isGlass ? 28 : 16 }

    public var accent: Color {
        isGlass ? Color.cyan : StrandPalette.accent
    }

    public var spring: Animation {
        isGlass
            ? .spring(response: 0.4, dampingFraction: 0.7)
            : StrandMotion.interactive
    }
}

private struct NoopAppearanceKey: EnvironmentKey {
    static let defaultValue: NoopAppearance = .classic
}

public extension EnvironmentValues {
    var noopAppearance: NoopAppearance {
        get { self[NoopAppearanceKey.self] }
        set { self[NoopAppearanceKey.self] = newValue }
    }
}

public extension View {
    func noopAppearance(_ appearance: NoopAppearance) -> some View {
        environment(\.noopAppearance, appearance)
    }
}

/// Layer 0. Classic is the green-black surface. Glass is a static dark mesh
/// (no forever-breathe — that hitch is why Classic still exists as a rollback).
public struct NoopScreenBackground: View {
    @Environment(\.noopAppearance) private var appearance

    public init() {}

    public var body: some View {
        Group {
            if appearance.isGlass {
                ZStack {
                    Color.black
                    RadialGradient(
                        colors: [Color.indigo.opacity(0.38), Color.cyan.opacity(0.10), .clear],
                        center: .topLeading,
                        startRadius: 8,
                        endRadius: 560
                    )
                    RadialGradient(
                        colors: [Color.pink.opacity(0.12), .clear],
                        center: .bottomTrailing,
                        startRadius: 4,
                        endRadius: 420
                    )
                }
            } else {
                StrandPalette.surfaceBase
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Specular glass edge

public struct NoopGlassStroke: View {
    public var cornerRadius: CGFloat

    public init(cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.40),
                        Color.clear,
                        Color.white.opacity(0.12)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }
}

public extension View {
    /// Glass cards: system material + specular edge. Classic: raised fill + hairline.
    @ViewBuilder
    func noopCardChrome(cornerRadius: CGFloat, hairline: Color = StrandPalette.hairline) -> some View {
        self
            .background { NoopCardFill(cornerRadius: cornerRadius) }
            .overlay { NoopCardEdge(cornerRadius: cornerRadius, hairline: hairline) }
    }
}

struct NoopCardFill: View {
    @Environment(\.noopAppearance) private var appearance
    var cornerRadius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if appearance.isGlass {
            shape.fill(.ultraThinMaterial)
        } else {
            shape.fill(StrandPalette.surfaceRaised)
        }
    }
}

struct NoopCardEdge: View {
    @Environment(\.noopAppearance) private var appearance
    var cornerRadius: CGFloat
    var hairline: Color

    var body: some View {
        if appearance.isGlass {
            NoopGlassStroke(cornerRadius: cornerRadius)
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(hairline, lineWidth: 1)
        }
    }
}
