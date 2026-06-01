import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: PlayerStore

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

#Preview {
    ContentView()
        .environmentObject(PlayerStore.shared)
}
