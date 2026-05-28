import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: PlayerStore

    var body: some View {
        ZStack {
            // Synthwave-y background gradient.
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.02, blue: 0.15),
                         Color(red: 0.20, green: 0.05, blue: 0.30)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 32) {
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
    }

    // MARK: – Subviews

    private var stationHeader: some View {
        VStack(spacing: 12) {
            Image(systemName: store.isPlaying ? "waveform" : "moon.stars")
                .font(.system(size: 80))
                .symbolEffect(.variableColor.iterative,
                              options: .repeating,
                              isActive: store.isPlaying)
                .foregroundStyle(.pink)

            Text(store.current?.name ?? "Tap play to start")
                .font(.title.bold())
                .multilineTextAlignment(.center)

            Text(store.nowPlayingText.isEmpty ? "Nightride FM" : store.nowPlayingText)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
    }

    private var transportControls: some View {
        HStack(spacing: 36) {
            Button { store.prev() } label: {
                Image(systemName: "backward.fill").font(.system(size: 32))
            }

            Button { store.togglePlayPause() } label: {
                Image(systemName: store.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 72))
            }

            Button { store.next() } label: {
                Image(systemName: "forward.fill").font(.system(size: 32))
            }
        }
        .foregroundStyle(.white)
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
            .background(.white.opacity(0.1), in: .rect(cornerRadius: 14))
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(PlayerStore.shared)
}
