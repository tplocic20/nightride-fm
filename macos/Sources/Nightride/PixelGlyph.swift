import SwiftUI
import AppKit

/// Pixel-art glyphs as string grids ('#' = filled). Rendered as crisp filled
/// cells tinted by the current colour — the native analogue of plocic.dev's
/// currentColor-masked pixel icons, with no SVG/asset pipeline.
enum PixelGlyph {
    // Transport — 11×11.
    static let play = [
        "..#........",
        "..##.......",
        "..###......",
        "..####.....",
        "..#####....",
        "..######...",
        "..#####....",
        "..####.....",
        "..###......",
        "..##.......",
        "..#........",
    ]

    static let pause = [
        "...........",
        "..##...##..",
        "..##...##..",
        "..##...##..",
        "..##...##..",
        "..##...##..",
        "..##...##..",
        "..##...##..",
        "..##...##..",
        "..##...##..",
        "...........",
    ]

    static let next = [
        ".#......#..",
        ".##.....#..",
        ".###....#..",
        ".####...#..",
        ".#####..#..",
        ".######.#..",
        ".#####..#..",
        ".####...#..",
        ".###....#..",
        ".##.....#..",
        ".#......#..",
    ]

    static let prev = [
        "..#......#.",
        "..#.....##.",
        "..#....###.",
        "..#...####.",
        "..#..#####.",
        "..#.######.",
        "..#..#####.",
        "..#...####.",
        "..#....###.",
        "..#.....##.",
        "..#......#.",
    ]

    // Menu-bar marks — the brand pixel sun on a fixed horizon. State is shown by
    // the sun's height: risen high with a ray gap when playing, set low when
    // paused (and drawn dimmer, see NightrideApp). Both grids are 11×9 so the
    // menu-bar slot never changes size between states.
    static let sunUp = [
        "...#####...",
        ".#########.",
        "###########",
        "###########",
        "###########",
        "###########",
        ".#########.",
        "...........",   // ray gap — sun radiating above the horizon
        "###########",   // horizon
    ]

    static let sunSet = [
        "...........",
        "...........",
        "...........",
        "...#####...",
        ".#########.",
        "###########",
        "###########",
        "...........",
        "###########",   // horizon — sun has set low into it
    ]

    /// Monochrome template NSImage for the menu-bar label; the system tints it.
    /// `alpha` dims the mark (template images respect source alpha) — used to
    /// fade the sun when paused.
    static func image(_ grid: [String], cell: CGFloat = 2, alpha: CGFloat = 1) -> NSImage {
        let rows = grid.count
        let cols = grid.map(\.count).max() ?? 0
        let size = NSSize(width: CGFloat(cols) * cell, height: CGFloat(rows) * cell)
        let image = NSImage(size: size, flipped: true) { _ in
            NSColor.black.withAlphaComponent(alpha).setFill()
            for (y, line) in grid.enumerated() {
                for (x, char) in line.enumerated() where char == "#" {
                    NSRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell,
                           width: cell, height: cell).fill()
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

/// Renders a pixel glyph crisply inside its frame, tinted by `color`.
struct PixelIcon: View {
    let grid: [String]
    var color: Color = Theme.onSurface

    var body: some View {
        Canvas { context, size in
            let rows = grid.count
            let cols = grid.map(\.count).max() ?? 0
            guard rows > 0, cols > 0 else { return }
            let cell = min(size.width / CGFloat(cols), size.height / CGFloat(rows))
            let ox = (size.width - cell * CGFloat(cols)) / 2
            let oy = (size.height - cell * CGFloat(rows)) / 2
            for (y, line) in grid.enumerated() {
                for (x, char) in line.enumerated() where char == "#" {
                    let rect = CGRect(x: ox + CGFloat(x) * cell,
                                      y: oy + CGFloat(y) * cell,
                                      width: cell, height: cell)
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
    }
}
