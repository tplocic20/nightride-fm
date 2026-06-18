import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: PlayerStore

    /// Brief "copied" confirmation state for the copy action chip.
    @State private var copied = false

    /// Whether the "About" sheet (attribution + contact) is showing.
    @State private var showAbout = false

    /// Current station's accent, or the Nightride magenta before anything plays.
    private var accent: Color { store.current?.accent ?? Color(hex: 0xCC55FF) }

    var body: some View {
        ZStack {
            background
            GeometryReader { geo in
                if min(geo.size.width, geo.size.height) >= 600 {
                    // Tablet: Spotify-style split — a responsive grid of station
                    // covers fills the left, the simple vertical "now playing"
                    // column sits on the right.
                    HStack(spacing: 0) {
                        stationGrid
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        VStack(spacing: 20) {
                            coverView(size: 200)
                            trackInfo
                            trackActions
                            transportControls
                        }
                        .padding(28)
                        .frame(width: 420)
                        .frame(maxHeight: .infinity)
                        .background(Color(hex: 0x140E1A).opacity(0.5))
                        .overlay(alignment: .leading) {
                            Rectangle().fill(accent.opacity(0.2)).frame(width: 1)
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                } else if geo.size.width > geo.size.height {
                    // Landscape: cover on the left, controls on the right, so the
                    // short vertical axis doesn't push anything off-screen.
                    HStack(spacing: 32) {
                        coverView(size: min(geo.size.height * 0.82, geo.size.width * 0.42))
                            .frame(maxWidth: .infinity)
                        VStack(spacing: 20) {
                            trackInfo
                            trackActions
                            transportControls
                            stationPicker
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 24)
                    .frame(width: geo.size.width, height: geo.size.height)
                } else {
                    // Portrait: a single centred vertical stack.
                    VStack(spacing: 28) {
                        Spacer()
                        VStack(spacing: 16) {
                            coverView(size: 224)
                            trackInfo
                            trackActions
                        }
                        Spacer()
                        transportControls
                        Spacer()
                        stationPicker
                            .padding(.bottom, 24)
                    }
                    .padding(.horizontal, 24)
                    .frame(width: geo.size.width, height: geo.size.height)
                }
            }
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.35), value: store.current?.id)
        .overlay(alignment: .bottom) {
            // Unobtrusive copy confirmation, floating above the safe area.
            if copied {
                Toast(text: "copied to clipboard", accent: accent)
                    .padding(.bottom, 36)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .overlay(alignment: .topTrailing) {
            // Discreet info button → "About" (attribution + contact).
            Button { showAbout = true } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("About")
        }
        .sheet(isPresented: $showAbout) {
            AboutView().presentationDetents([.medium])
        }
    }

    /// Flash the copy toast for ~1.4s.
    private func showToast() {
        withAnimation(.easeInOut(duration: 0.25)) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.easeInOut(duration: 0.25)) { copied = false }
        }
    }

    /// Responsive grid of station covers — iPad's left pane. Vertically centred,
    /// and scrolls only if the covers ever exceed the height.
    private var stationGrid: some View {
        GeometryReader { proxy in
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 16) {
                    ForEach(Stations.all) { station in
                        stationTile(station)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
        }
    }

    @ViewBuilder
    private func stationTile(_ station: Station) -> some View {
        let isCurrent = store.current?.id == station.id
        Button {
            store.play(station)
        } label: {
            VStack(spacing: 8) {
                Group {
                    if let image = Artwork.image(for: station) {
                        Image(uiImage: image)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                    } else {
                        Color(hex: 0x140E1A)
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .overlay(
                    Rectangle().strokeBorder(
                        isCurrent ? station.accent : .white.opacity(0.15),
                        lineWidth: isCurrent ? 2 : 1
                    )
                )
                .shadow(color: isCurrent ? station.accent.opacity(0.5) : .clear, radius: 12)

                Text(station.name.lowercased())
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(isCurrent ? station.accent : .white.opacity(0.8))
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: – Subviews

    // Dark, constant ground with a subtle per-station tint — distinct enough to
    // tell stations apart without ever hurting text contrast.
    private var background: some View {
        ZStack {
            Color(hex: 0x0E0A12)
            RadialGradient(colors: [accent.opacity(0.22), .clear],
                           center: .center, startRadius: 0, endRadius: 440)
        }
        .ignoresSafeArea()
    }

    /// Station name + the live "Artist — Title" line (no cover/chips) so the
    /// landscape layout can place them beside the cover.
    private var trackInfo: some View {
        VStack(spacing: 16) {
            Text(store.current?.name ?? "Tap play to start")
                .font(.title.bold())
                .multilineTextAlignment(.center)

            // Reserve both lines so a wrapping title doesn't nudge the layout as
            // tracks change.
            Text(store.nowPlaying?.display.isEmpty == false ? store.nowPlaying!.display : "Nightride FM")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)
        }
    }

    /// Quick "I love this song" row — search the live track on a streaming
    /// service or copy "Artist — Title". Only shown when a real track is known.
    @ViewBuilder
    private var trackActions: some View {
        if let track = store.nowPlaying, !track.isEmpty {
            HStack(spacing: 8) {
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
        }
    }

    @ViewBuilder
    private func coverView(size: CGFloat) -> some View {
        if let station = store.current, let image = Artwork.image(for: station) {
            Image(uiImage: image)
                .resizable()
                .interpolation(.none)   // keep the pixel art crisp when scaled
                .scaledToFit()
                .frame(width: size, height: size)
                .overlay(Rectangle().strokeBorder(accent.opacity(0.6), lineWidth: 1))
                .shadow(color: accent.opacity(0.5), radius: 24)
        } else {
            Image(systemName: store.isPlaying ? "waveform" : "moon.stars")
                .font(.system(size: min(size * 0.36, 80)))
                .symbolEffect(.variableColor.iterative,
                              options: .repeating,
                              isActive: store.isPlaying)
                .foregroundStyle(accent)
        }
    }

    private var transportControls: some View {
        HStack(spacing: 36) {
            Button { store.prev() } label: {
                Image(systemName: "backward.fill").font(.system(size: 30))
            }
            .foregroundStyle(.white)

            Button { store.togglePlayPause() } label: {
                Image(systemName: store.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 72))
            }
            .foregroundStyle(accent)
            .shadow(color: accent.opacity(0.55), radius: 12)

            Button { store.next() } label: {
                Image(systemName: "forward.fill").font(.system(size: 30))
            }
            .foregroundStyle(.white)
        }
    }

    private var stationPicker: some View {
        Menu {
            ForEach(Stations.all) { st in
                Button {
                    store.play(st)
                } label: {
                    if store.current?.id == st.id {
                        Label(st.name, systemImage: "speaker.wave.2.fill")
                    } else {
                        Text(st.name)
                    }
                }
            }
        } label: {
            HStack {
                Image(systemName: "list.bullet")
                Text("Stations")
                Spacer()
                Image(systemName: "chevron.up")
            }
            .padding()
            .background(.white.opacity(0.08), in: .rect(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(accent.opacity(0.4), lineWidth: 1)
            )
        }
    }
}

/// Tiny non-intrusive confirmation pill (e.g. after copying). Translucent dark
/// capsule with a thin accent edge — reads as part of the synthwave chrome.
private struct Toast: View {
    let text: String
    var accent: Color = Color(hex: 0xCC55FF)

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(Capsule().fill(Color(hex: 0x1D1422).opacity(0.92)))
            .overlay(Capsule().strokeBorder(accent.opacity(0.6), lineWidth: 1))
            .shadow(color: accent.opacity(0.45), radius: 8)
    }
}

/// Small text chip for the quick-search / copy actions under the track.
private struct ActionChip: View {
    let label: String
    var accent: Color = Color(hex: 0xCC55FF)
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .fixedSize()
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(accent.opacity(0.5), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

/// Small "About" sheet — personal attribution + where to reach the author.
/// The repo is public, so bug reports go to GitHub Issues.
private struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private let accent = Color(hex: 0xCC55FF)

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Full-bleed dark ground so the sheet matches the app's chrome.
            Color(hex: 0x0E0A12).ignoresSafeArea()

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")

            VStack(spacing: 12) {
                Text("Nightride.fm Player")
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                Text("v\(version)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))

                Text("Made by Tomasz Plocic")
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.top, 2)

                HStack(spacing: 10) {
                    AboutLink(label: "plocic.dev",
                              url: "https://plocic.dev", accent: accent)
                    AboutLink(label: "report a bug ↗",
                              url: "https://github.com/tplocic20/nightride-fm/issues", accent: accent)
                }
                .padding(.top, 2)

                Text("Unofficial fan project — not affiliated with Nightride FM.")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 6)
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .preferredColorScheme(.dark)
    }
}

/// Bordered mono link chip used inside the About sheet.
private struct AboutLink: View {
    let label: String
    let url: String
    let accent: Color

    var body: some View {
        Link(label, destination: URL(string: url)!)
            .font(.system(size: 13, weight: .medium, design: .monospaced))
            .foregroundStyle(accent)
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(accent.opacity(0.5), lineWidth: 1)
            )
    }
}

#Preview {
    ContentView()
        .environmentObject(PlayerStore.shared)
}
