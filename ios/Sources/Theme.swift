import SwiftUI

/// Two looks, no more: **midnight** (per-station accent on dark, the classic)
/// and **amber** (monochrome phosphor CRT — one hue, scanlines, text glow).
/// A radio app plays at night; anything lighter than these two would be noise.
enum Theme: String, CaseIterable, Identifiable {
    case midnight
    case amber

    var id: String { rawValue }

    var label: String { rawValue }

    /// Ground beneath everything else.
    var ground: Color {
        switch self {
        case .midnight: return Color(hex: 0x0E0A12)
        case .amber: return Color(hex: 0x0C0903)
        }
    }

    /// Amber is deliberately mono — the theme color wins over station accents,
    /// which is what makes the whole screen read as one phosphor tube.
    var overridesAccent: Bool {
        self == .amber
    }

    /// Horizontal CRT scanline overlay drawn in a single Canvas pass.
    var scanlines: some View {
        Canvas { ctx, size in
            var y: CGFloat = 0
            while y < size.height {
                ctx.fill(
                    Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                    with: .color(.black.opacity(0.16))
                )
                y += 3
            }
        }
        .allowsHitTesting(false)
    }
}
