import SwiftUI

@main
struct NightrideApp: App {
    @StateObject private var store = PlayerStore()

    var body: some Scene {
        MenuBarExtra {
            PlayerView(store: store)
                .onAppear { RemoteCommands.install(store) }
        } label: {
            // Brand pixel sun: risen + full when playing, set + dimmed when idle.
            Image(nsImage: store.isPlaying
                ? PixelGlyph.image(PixelGlyph.sunUp)
                : PixelGlyph.image(PixelGlyph.sunSet, alpha: 0.55))
        }
        .menuBarExtraStyle(.window)
    }
}
