import SwiftUI

// Suite-inspired identity: a deep navy surface with a faint isometric grid, lit
// gently toward the center, and a single vivid cobalt-blue accent. Clean
// hierarchy, rounded cards, restrained motion.

extension Color {
    init(hex: UInt, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

enum Palette {
    // Deep indigo-navy base. Edges sit at `canvas`; `canvasLift` glows toward center.
    static let canvas       = Color(hex: 0x0B0E1C)
    static let canvasLift   = Color(hex: 0x171C38)
    // Solid panels for sheets / pages (no behind-window vibrancy).
    static let windowTop    = Color(hex: 0x161B34)
    static let windowBottom = Color(hex: 0x0B0E1C)

    // Electric iris/indigo accent: our signature. Bluer than violet, more
    // characterful than cobalt; a nod to the original symlink magenta.
    static let accent       = Color(hex: 0x6A5CF6)
    static let accentLight  = Color(hex: 0x9D93FF)
    static let accentDeep   = Color(hex: 0x4A3DD6)
    static let cream        = Color(hex: 0xECEAFF)
    static let warn         = Color(hex: 0xD9A441)   // amber: caution, not an error

    static let ink          = Color.white.opacity(0.95)
    static let ink55        = Color(hex: 0x9CA0C4)   // muted lavender-gray secondary
    static let ink45        = Color(hex: 0x6E7299)   // tertiary
    static let ink30        = Color(hex: 0x4E527C)   // labels / faint

    static let card         = Color.white.opacity(0.04)
    static let fieldFill     = Color.white.opacity(0.05)
    static let hairline      = Color.white.opacity(0.09)
    static let gridLine      = Color(hex: 0x9D93FF, opacity: 0.05)
    static let selection     = Color(hex: 0x6A5CF6, opacity: 0.20)
}

/// A control surface: faint fill, hairline border.
struct FieldBackground: ViewModifier {
    var radius: CGFloat = 9
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Palette.fieldFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 1)
            )
    }
}

/// A grouping surface (a Suite-style card): a slightly raised navy panel.
struct CardBackground: ViewModifier {
    var radius: CGFloat = 14
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Palette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 1)
            )
    }
}

extension View {
    func fieldStyle(radius: CGFloat = 9) -> some View { modifier(FieldBackground(radius: radius)) }
    func cardStyle(radius: CGFloat = 14) -> some View { modifier(CardBackground(radius: radius)) }
}

/// A gentle press: a small scale + dim, spring-settled. Respects reduced motion.
struct PressableStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduce
    var scale: CGFloat = 0.97
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduce ? scale : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(reduce ? nil : .spring(response: 0.26, dampingFraction: 0.7),
                       value: configuration.isPressed)
    }
}

/// Solid background for sheets (which have no behind-window vibrancy).
struct SheetBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.windowTop, Palette.windowBottom],
                           startPoint: .top, endPoint: .bottom)
            ConnectorMesh(line: Palette.gridLine.opacity(0.7))
        }
    }
}
