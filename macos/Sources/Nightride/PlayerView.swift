import SwiftUI
import AppKit

/// The themed popover shown by the MenuBarExtra (`.window` style). Replaces the
/// old native NSMenu so we can run the pixel/mono synthwave treatment.
struct PlayerView: View {
    @ObservedObject var store: PlayerStore

    /// Current station's accent, or the Nightride magenta before anything plays.
    private var accent: Color { store.current?.accent ?? Theme.primary }

    var body: some View {
        ZStack {
            Theme.bg
            content.padding(16)
        }
        .frame(width: 300)
        .foregroundStyle(Theme.onSurface)
        .animation(.easeInOut(duration: 0.3), value: store.current?.id)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            transport
            stationList
            footer
        }
    }

    // MARK: – Header (cover + now playing + attribution)

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            if let station = store.current, let image = Artwork.image(for: station) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)   // keep the pixel art crisp
                    .frame(width: 60, height: 60)
                    .overlay(Rectangle().strokeBorder(accent.opacity(0.6), lineWidth: 1))
                    .phosphorGlow(accent, radius: 8, active: store.isPlaying)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("> now playing")
                    .font(Theme.mono(11, weight: .medium))
                    .tracking(1.5)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.secondary.opacity(0.8))

                Text(store.current?.name ?? "Nightride FM")
                    .font(Theme.display(18, weight: .semibold))
                    .foregroundStyle(store.isPlaying ? accent : Theme.onSurface)
                    .phosphorGlow(accent, radius: 8, active: store.isPlaying)
                    .lineLimit(1)

                attribution
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var attribution: some View {
        let track = store.nowPlaying
        if let track, !track.isEmpty {
            Text(track.title.isEmpty ? track.artist : track.title)
                .font(Theme.mono(12))
                .foregroundStyle(Theme.onSurface)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if !track.artist.isEmpty {
                Text(track.artist)
                    .font(Theme.mono(11))
                    .foregroundStyle(accent)
                    .lineLimit(1)
            }
        } else {
            Text(store.current == nil ? "select a station" : "…")
                .font(Theme.mono(12))
                .foregroundStyle(Theme.onSurfaceVar)
        }
    }

    // MARK: – Transport

    private var transport: some View {
        HStack(spacing: 10) {
            TransportButton(grid: PixelGlyph.prev, accent: accent, action: store.prev)
            TransportButton(
                grid: store.isPlaying ? PixelGlyph.pause : PixelGlyph.play,
                size: 46,
                tint: accent,
                accent: accent,
                action: store.togglePlayPause
            )
            TransportButton(grid: PixelGlyph.next, accent: accent, action: store.next)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: – Stations

    private var stationList: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("stations")
                .font(Theme.mono(11, weight: .medium))
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundStyle(Theme.onSurfaceVar.opacity(0.7))
                .padding(.bottom, 2)

            ForEach(Stations.all) { station in
                StationRow(
                    station: station,
                    isCurrent: store.current?.id == station.id,
                    isPlaying: store.isPlaying,
                    action: { store.play(station) }
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: – Footer (cross-links + quit)

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle()
                .fill(Theme.outlineVar)
                .frame(height: 1)

            HStack(spacing: 14) {
                LinkButton(label: "↗ nightride.fm", url: "https://nightride.fm")
                LinkButton(label: "↗ discord", url: "https://discord.gg/synthwave")
                Spacer(minLength: 0)
                FooterButton(label: "quit ▸") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(.top, 2)
    }
}

// MARK: – Sub-views

private struct TransportButton: View {
    let grid: [String]
    var size: CGFloat = 38
    var tint: Color = Theme.onSurface
    var accent: Color = Theme.primary
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            PixelIcon(grid: grid, color: hover ? accent : tint)
                .frame(width: size * 0.52, height: size * 0.52)
                .frame(width: size, height: size)
                .background(Theme.surface2)
                .overlay(
                    Rectangle()
                        .strokeBorder(hover ? accent : Theme.outlineVar, lineWidth: 1)
                )
                .phosphorGlow(accent, radius: 6, active: hover)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

private struct StationRow: View {
    let station: Station
    let isCurrent: Bool
    let isPlaying: Bool
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(isCurrent ? ">" : "/")
                    .foregroundStyle(isCurrent ? station.accent : Theme.outline)
                Text(station.name.lowercased())
                    .foregroundStyle(labelColor)
                Spacer(minLength: 0)
            }
            .font(Theme.mono(12))
            .padding(.vertical, 3)
            .padding(.horizontal, 4)
            .background(hover ? Theme.surface2 : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }

    private var labelColor: Color {
        if isCurrent { return station.accent }
        return hover ? Theme.onSurface : Theme.onSurfaceVar
    }
}

private struct LinkButton: View {
    let label: String
    let url: String

    @State private var hover = false

    var body: some View {
        Button {
            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        } label: {
            Text(label)
                .font(Theme.mono(11))
                .foregroundStyle(hover ? Theme.secondary : Theme.onSurfaceVar.opacity(0.8))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

private struct FooterButton: View {
    let label: String
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Theme.mono(11))
                .foregroundStyle(hover ? Theme.secondary : Theme.onSurfaceVar.opacity(0.8))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
