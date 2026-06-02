import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: PlayerStore

    /// Brief "copied" confirmation state for the copy action chip.
    @State private var copied = false

    /// Current station's accent, or the Nightride magenta before anything plays.
    private var accent: Color { store.current?.accent ?? Color(hex: 0xCC55FF) }

    var body: some View {
        ZStack {
            background
            VStack(spacing: 28) {
                Spacer()
                stationHeader
                Spacer()
                transportControls
                Spacer()
                stationPicker
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 24)
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
    }

    /// Flash the copy toast for ~1.4s.
    private func showToast() {
        withAnimation(.easeInOut(duration: 0.25)) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.easeInOut(duration: 0.25)) { copied = false }
        }
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

    private var stationHeader: some View {
        VStack(spacing: 16) {
            cover

            Text(store.current?.name ?? "Tap play to start")
                .font(.title.bold())
                .multilineTextAlignment(.center)

            // Reserve both lines so a wrapping title doesn't nudge the cover /
            // station name up and down as tracks change.
            Text(store.nowPlaying?.display.isEmpty == false ? store.nowPlaying!.display : "Nightride FM")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)

            trackActions
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
    private var cover: some View {
        if let station = store.current, let image = Artwork.image(for: station) {
            Image(uiImage: image)
                .resizable()
                .interpolation(.none)   // keep the pixel art crisp when scaled
                .scaledToFit()
                .frame(width: 224, height: 224)
                .overlay(Rectangle().strokeBorder(accent.opacity(0.6), lineWidth: 1))
                .shadow(color: accent.opacity(0.5), radius: 24)
        } else {
            Image(systemName: store.isPlaying ? "waveform" : "moon.stars")
                .font(.system(size: 80))
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

#Preview {
    ContentView()
        .environmentObject(PlayerStore.shared)
}
