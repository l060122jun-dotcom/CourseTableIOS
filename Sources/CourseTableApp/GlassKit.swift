import SwiftUI

// MARK: - Liquid Glass design system
//
// Performance notes (why this file looks the way it does):
//   * The backdrop is a SINGLE static `MeshGradient` — one GPU draw call, no
//     per-frame work. Any animated backdrop forces every glass element on top
//     to re-sample it each frame, which is the main source of jank.
//   * Glass cards use one material + one gradient + one hairline + one soft
//     shadow. Shadows and stacked overlays are the expensive part, so they are
//     kept minimal.

enum GlassPalette {
    static let surface = Color.white
    static let accent = Color(red: 0.05, green: 0.47, blue: 1.0)

    /// Backdrop base colours that adapt to the active appearance.
    static func backdropColors(for scheme: ColorScheme) -> [Color] {
        if scheme == .dark {
            return [
                Color(red: 0.05, green: 0.06, blue: 0.12),
                Color(red: 0.07, green: 0.08, blue: 0.16),
                Color(red: 0.10, green: 0.07, blue: 0.17),
                Color(red: 0.06, green: 0.09, blue: 0.16),
                Color(red: 0.11, green: 0.07, blue: 0.16),
                Color(red: 0.14, green: 0.08, blue: 0.17),
                Color(red: 0.05, green: 0.12, blue: 0.16),
                Color(red: 0.07, green: 0.10, blue: 0.17),
                Color(red: 0.06, green: 0.11, blue: 0.15)
            ]
        }
        return [
            Color(red: 0.91, green: 0.93, blue: 1.00),
            Color(red: 0.86, green: 0.89, blue: 1.00),
            Color(red: 0.93, green: 0.89, blue: 1.00),
            Color(red: 0.84, green: 0.91, blue: 1.00),
            Color(red: 0.93, green: 0.88, blue: 1.00),
            Color(red: 0.98, green: 0.91, blue: 0.97),
            Color(red: 0.87, green: 0.97, blue: 0.99),
            Color(red: 0.91, green: 0.95, blue: 1.00),
            Color(red: 0.89, green: 0.96, blue: 0.99)
        ]
    }

    static func color(fromHex hex: String) -> Color {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let int = UInt64(value, radix: 16) else { return accent }
        return Color(
            red: Double((int >> 16) & 0xFF) / 255.0,
            green: Double((int >> 8) & 0xFF) / 255.0,
            blue: Double(int & 0xFF) / 255.0
        )
    }
}

// MARK: - Backportable glass modifier

enum GlassStyle {
    case regular
    case thin
    case tinted(Color)
    case interactiveTinted(Color)

    @available(iOS 26.0, *)
    var native: Glass {
        switch self {
        case .regular, .thin: return .regular
        case .tinted(let color), .interactiveTinted(let color): return .regular.tint(color)
        }
    }

    var isInteractive: Bool {
        if case .interactiveTinted = self { return true }
        return false
    }

    var tintColor: Color? {
        switch self {
        case .tinted(let color), .interactiveTinted(let color): return color
        default: return nil
        }
    }
}

extension View {
    /// Liquid Glass with a graceful fallback for iOS 17–25.
    @ViewBuilder
    func liuyunGlass<S: InsettableShape>(_ style: GlassStyle = .regular, in shape: S = Capsule(), stroke: Bool = true) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(style.native, in: shape)
        } else {
            self.background(
                shape
                    .fill(style.tintColor?.opacity(0.28) ?? Color.clear)
                    .background(shape.fill(.ultraThinMaterial))
                    .overlay(
                        LinearGradient(
                            colors: [.white.opacity(0.45), .white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .clipShape(shape)
                        .allowsHitTesting(false)
                    )
                    .overlay(stroke ? shape.strokeBorder(.white.opacity(0.35), lineWidth: 0.75) : nil)
            )
        }
    }
}

// MARK: - Atmospheric backdrop (static, one draw call)

/// A calm, static pastel mesh. Rendered once and cached by the compositor, so
/// glass elements above it never have to re-sample a moving backdrop.
struct GlassBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        MeshGradient(
            width: 3,
            height: 3,
            points: [
                .init(0.0, 0.0), .init(0.5, 0.0), .init(1.0, 0.0),
                .init(0.0, 0.5), .init(0.48, 0.46), .init(1.0, 0.5),
                .init(0.0, 1.0), .init(0.5, 1.0), .init(1.0, 1.0)
            ],
            colors: GlassPalette.backdropColors(for: scheme)
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - Glass card

/// A layered translucent container: an inner glass fill, a soft gradient and a
/// single hairline. Kept deliberately light — no stacked shadows.
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 22
    var tint: Color? = nil
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    @Environment(\.colorScheme) private var scheme

    private var highlight: [Color] {
        scheme == .dark
            ? [.white.opacity(0.14), .white.opacity(0.02)]
            : [.white.opacity(0.5), .white.opacity(0.06)]
    }

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: highlight,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay {
                        if let tint {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(tint.opacity(0.14))
                        }
                    }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(scheme == .dark ? 0.18 : 0.4), lineWidth: 0.75)
            )
            .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.08), radius: 12, x: 0, y: 6)
    }
}

// MARK: - Glass action button

struct GlassActionButton: View {
    var title: String
    var systemImage: String?
    var tint: Color = GlassPalette.accent
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage).font(.system(size: 14, weight: .semibold)) }
                Text(title).font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.14))
                    .overlay(Capsule(style: .continuous).strokeBorder(.white.opacity(0.6), lineWidth: 0.75))
            )
        }
        .buttonStyle(.plain)
    }
}
