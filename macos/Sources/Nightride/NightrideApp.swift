import SwiftUI

@main
struct NightrideApp: App {
    @StateObject private var store = PlayerStore()

    var body: some Scene {
        MenuBarExtra {
            PlayerView(store: store)
                .onAppear { RemoteCommands.install(store) }
        } label: {
            Image(nsImage: PixelGlyph.image(store.isPlaying ? PixelGlyph.waveform : PixelGlyph.moon))
        }
        .menuBarExtraStyle(.window)
    }
}
