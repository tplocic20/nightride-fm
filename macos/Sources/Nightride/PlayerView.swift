import SwiftUI
import AppKit

/// The themed popover shown by the MenuBarExtra (`.window` style). Replaces the
/// old native NSMenu so we can run the pixel/mono synthwave treatment.
struct PlayerView: View {
    @ObservedObject var store: PlayerStore

    /// Brief "copied" confirmation state for the copy action chip.
    @State private var copied = false

    /// Current station's accent, or the Nightride magenta before anything plays.
    private var accent: Color { store.current?.accent ?? Theme.primary }

    var body: some View {
        ZStack {
            Theme.bg
            content.padding(16)

            // Unobtrusive copy confirmation, pinned to the bottom edge.
            if copied {
                Toast(text: "copied to clipboard", accent: accent)
                    .padding(.bottom, 14)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .frame(width: 340)
        .foregroundStyle(Theme.onSurface)
        // No scoped `.animation(value:)` here — every transition is driven by a
        // single `withAnimation(Theme.transition)` in PlayerStore, so the whole
        // view animates in one transaction and nothing snaps independently.
    }

    /// Flash the copy toast for ~1.4s.
    private func showToast() {
        withAnimation(Theme.transition) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(Theme.transition) { copied = false }
        }
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
                trackActions
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Quick "I love this song" row — search the live track on a streaming
    /// service or copy "Artist — Title". Only shown when a real track is known.
    @ViewBuilder
    private var trackActions: some View {
        if let track = store.nowPlaying, !track.isEmpty {
            HStack(spacing: 6) {
                ForEach(MusicService.allCases) { service in
                    ActionChip(label: service.label, accent: accent) {
                        MusicSearch.open(service, for: track)
                    }
                }
                ActionChip(label: "copy", accent: accent) {
                    MusicSearch.copy(track)
                    showToast()
                }
            }
            .padding(.top, 4)
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

            // A 2×2 grid of external links — station links on the top row,
            // author/source on the bottom — given the footer's full width so
            // labels never truncate. The Grid keeps the two columns aligned
            // despite differing label widths. The public repo's Issues page is
            // the bug tracker.
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    LinkButton(label: "↗ nightride.fm", url: "https://nightride.fm")
                    LinkButton(label: "↗ discord", url: "https://discord.com/invite/synthwave")
                }
                GridRow {
                    LinkButton(label: "↗ plocic.dev", url: "https://plocic.dev")
                    LinkButton(label: "↗ report a bug",
                               url: "https://github.com/tplocic20/nightride-fm/issues")
                }
            }

            // quit on its own line, right-aligned beneath the grid.
            HStack {
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

/// Tiny non-intrusive confirmation pill (e.g. after copying). Translucent dark
/// capsule with a thin accent edge and a small phosphor glow — reads as part of
/// the CRT chrome, not a system alert.
private struct Toast: View {
    let text: String
    var accent: Color = Theme.primary

    var body: some View {
        Text(text)
            .font(Theme.mono(10, weight: .medium))
            .tracking(0.5)
            .foregroundStyle(Theme.onSurface)
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(
                Capsule().fill(Theme.surface2.opacity(0.92))
            )
            .overlay(
                Capsule().strokeBorder(accent.opacity(0.6), lineWidth: 1)
            )
            .phosphorGlow(accent, radius: 6)
    }
}

/// Small mono-text chip for the quick-search / copy actions under the track.
private struct ActionChip: View {
    let label: String
    var accent: Color = Theme.primary
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Theme.mono(10, weight: .medium))
                .lineLimit(1)
                .fixedSize()        // service labels are short + fixed — never wrap
                .foregroundStyle(hover ? accent : Theme.onSurfaceVar)
                .padding(.vertical, 3)
                .padding(.horizontal, 7)
                .overlay(
                    Rectangle()
                        .strokeBorder(hover ? accent : Theme.outlineVar, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

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
                // Selection glyph + colour flip instantly: PlayerStore changes
                // `current` outside its animated transaction, so only the track
                // change animates. That keeps the `/`→`>` swap snappy (no laggy
                // cross-dissolve) while letting every row — including the newly-
                // and previously-selected ones — glide with the layout.
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
                .fixedSize()   // never truncate the link label
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
