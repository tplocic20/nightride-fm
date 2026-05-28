import SwiftUI

@main
struct NightrideApp: App {
    @StateObject private var store = PlayerStore()

    init() {
        // SwiftUI doesn't give us a hook to run code with @StateObject during
        // init(), so we register remote commands lazily on appear instead.
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(store: store)
                .onAppear { RemoteCommands.install(store) }
        } label: {
            Image(systemName: store.isPlaying ? "waveform" : "moon.stars")
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct MenuContent: View {
    @ObservedObject var store: PlayerStore

    var body: some View {
        if let cur = store.current {
            Text(cur.name)
            if !store.nowPlayingText.isEmpty {
                Text(store.nowPlayingText)
            }
            Divider()
        }

        Button(store.isPlaying ? "Pause" : (store.current == nil ? "Play Nightride FM" : "Play")) {
            store.togglePlayPause()
        }
        .keyboardShortcut("p")

        Button("Next Station") { store.next() }.keyboardShortcut("]")
        Button("Previous Station") { store.prev() }.keyboardShortcut("[")

        Divider()
        Text("Stations")
        ForEach(Stations.all) { st in
            Button {
                store.play(st)
            } label: {
                if store.current?.id == st.id && store.isPlaying {
                    Label(st.name, systemImage: "speaker.wave.2.fill")
                } else {
                    Text(st.name)
                }
            }
        }

        Divider()
        Button("Quit Nightride") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
