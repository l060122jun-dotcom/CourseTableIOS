import SwiftUI

// MARK: - Liquid Glass design system
//
// A small, dependency-free design language shared by every screen:
//   * `GlassBackground`  – atmospheric layered backdrop (blurred color blobs) that
//                          the glass elements refract.
//   * `.liuyunGlass`     – Liquid Glass on iOS 26, an `ultraThinMaterial` +
//                          gradient + hairline stroke everywhere else.
//   * `DropIndicator`    – a morphing "water drop" capsule used by selectors.
//   * `GlassCard`        – a layered, translucent card container.
//
// Reference: Apple "Applying Liquid Glass to custom views" (WWDC25) and the
// widely-used backport pattern from netanel.io / conorluddy.

enum GlassPalette {
    /// Neutral glass surface used for cards, sheets and chips.
    static let surface = Color.white
    /// Accent used for the primary call to action.
    static let accent = Color(red: 0.05, green: 0.47, blue: 1.0)
    /// Atmospheric tints behind the content plane.
    static let aurora: [Color] = [
        Color(red: 0.45, green: 0.58, blue: 1.00),
        Color(red: 0.78, green: 0.51, blue: 1.00),
        Color(red: 0.40, green: 0.90, blue: 0.94),
        Color(red: 0.98, green: 0.66, blue: 0.86)
    ]

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
            if style.isInteractive {
                self.glassEffect(style.native, in: shape)
            } else {
                self.glassEffect(style.native, in: shape)
            }
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

// MARK: - Atmospheric backdrop

/// A layered backdrop: a soft gradient plus slow-moving colour blobs. The
/// blur gives the glass something meaningful to refract, which is what sells
/// the "liquid" look.
struct GlassBackground: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.93, green: 0.95, blue: 1.0),
                    Color(red: 0.97, green: 0.94, blue: 1.0),
                    Color(red: 0.92, green: 0.97, blue: 0.99)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            GeometryReader { proxy in
                let size = proxy.size
                ZStack {
                    blob(GlassPalette.aurora[0], size: size.width * 0.85, offset: offset(x: -0.28, y: -0.30, size: size))
                    blob(GlassPalette.aurora[1], size: size.width * 0.75, offset: offset(x: 0.34, y: -0.12, size: size))
                    blob(GlassPalette.aurora[2], size: size.width * 0.80, offset: offset(x: -0.10, y: 0.38, size: size))
                    blob(GlassPalette.aurora[3], size: size.width * 0.62, offset: offset(x: 0.30, y: 0.42, size: size))
                }
                .blur(radius: 60)
                .opacity(0.55)
                .offset(y: animate ? 12 : -12)
                .animation(.easeInOut(duration: 9).repeatForever(autoreverses: true), value: animate)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
        .onAppear { animate = true }
    }

    private func blob(_ color: Color, size: CGFloat, offset: CGPoint) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .position(offset)
    }

    private func offset(x: CGFloat, y: CGFloat, size: CGSize) -> CGPoint {
        CGPoint(x: size.width * (0.5 + x), y: size.height * (0.5 + y))
    }
}

// MARK: - Glass card

/// A layered translucent container: an outer hairlight, an inner glass fill and
/// an optional accent glow. Mimics Apple's multi-layer sheet material.
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 22
    var tint: Color? = nil
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

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
                                    colors: [.white.opacity(0.55), .white.opacity(0.08)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(tint?.opacity(0.16) ?? Color.clear)
                    }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.4), lineWidth: 0.75)
            )
            .shadow(color: .black.opacity(0.10), radius: 18, x: 0, y: 10)
    }
}

// MARK: - Water-drop indicator

/// A morphing "water drop" pill that slides behind the selected item. Uses
/// `matchedGeometryEffect` so it stretches like a droplet when moving between
/// items of different widths, then settles into a rounded blob.
struct DropIndicator<ID: Hashable>: ViewModifier {
    let id: ID
    let namespace: Namespace.ID
    var tint: Color = GlassPalette.accent

    func body(content: Content) -> some View {
        content
            .background(
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.92), tint.opacity(0.66)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(.white.opacity(0.5), lineWidth: 0.75)
                    )
                    .shadow(color: tint.opacity(0.35), radius: 10, x: 0, y: 4)
                    .matchedGeometryEffect(id: id, in: namespace)
            )
    }
}

extension View {
    func dropIndicator<ID: Hashable>(_ id: ID, in namespace: Namespace.ID, tint: Color = GlassPalette.accent) -> some View {
        modifier(DropIndicator(id: id, namespace: namespace, tint: tint))
    }
}

// MARK: - Reusable glass button

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
            .liuyunGlass(.interactiveTinted(tint), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
