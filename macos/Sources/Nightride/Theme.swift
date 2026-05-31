import SwiftUI

/// Phosphor-synthwave palette — plocic.dev's token structure and CRT/pixel/mono
/// language, recoloured to neon-on-warm-black so the app still reads as a
/// synthwave radio rather than a dev tool. Shared concept across all clients.
enum Theme {
    static let bg           = Color(hex: 0x0E0A12)   // flat near-black, faint violet
    static let surface1     = Color(hex: 0x161019)
    static let surface2     = Color(hex: 0x1D1422)
    static let surface3     = Color(hex: 0x281B2F)
    static let onSurface    = Color(hex: 0xECE6F0)   // cool off-white
    static let onSurfaceVar = Color(hex: 0xB9A9C4)   // muted lavender-grey
    static let primary      = Color(hex: 0xFF4D9D)   // neon magenta (carried over)
    static let secondary    = Color(hex: 0x54E6E6)   // cyan
    static let tertiary     = Color(hex: 0xB388FF)   // electric violet
    static let outline      = Color(hex: 0x6E5A78)
    static let outlineVar   = Color(hex: 0x3A2C42)

    // Type: SF Mono for all UI chrome, SF for the single station-name headline.
    // (Bundling JetBrains Mono + Montserrat is a later cross-platform polish.)
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

extension View {
    /// Subtle phosphor bloom on accent text/glyphs. No-op when inactive.
    func phosphorGlow(_ color: Color, radius: CGFloat = 6, active: Bool = true) -> some View {
        shadow(color: active ? color.opacity(0.7) : .clear, radius: active ? radius : 0)
    }
}
