import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: PlayerStore

    /// CRT scanline overlay, off by default. Seeds itself from the old amber
    /// theme key so anyone who had amber keeps their scanlines.
    @AppStorage("scanlines") private var scanlinesOn =
        UserDefaults.standard.string(forKey: "theme") == "amber"

    /// Whether the artwork easter egg is flipped to the spectrum side.
    @State private var artFlipped = false

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
        .overlay { if scanlinesOn { Scanlines() } }
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
            HStack(spacing: 4) {
                sleepTimerMenu
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
        }
        .sheet(isPresented: $showAbout) {
            AboutView().presentationDetents([.medium])
        }
    }

    /// Sleep timer picker — moon turns accent and counts down while armed.
    private var sleepTimerMenu: some View {
        Menu {
            ForEach([15, 30, 60], id: \.self) { m in
                Button("\(m) min") { store.startSleepTimer(minutes: m) }
            }
            if store.sleepTimerRemaining != nil {
                Button("off", role: .destructive) { store.cancelSleepTimer() }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "moon.zzz")
                    .font(.system(size: 18))
                if let remaining = store.sleepTimerRemaining {
                    Text(timeString(remaining))
                        .font(.system(size: 13, design: .monospaced))
                }
            }
            .foregroundStyle(store.sleepTimerRemaining != nil ? accent : .white.opacity(0.45))
            .padding(16)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Sleep timer")
    }

    private func timeString(_ t: TimeInterval) -> String {
        String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
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

    // Station-tinted ground: dark base, a wide radial wash of the station's
    // accent, and a soft glow bleeding from the artwork position — the screen
    // visibly "belongs" to the station without hurting text contrast.
    private var background: some View {
        ZStack {
            Color(hex: 0x0E0A12)
            // Full-bleed artwork: the station's cover fills the screen, blurred
            // into a color field — the artwork itself becomes the tint. Color.clear
            // + overlay + clipped so the fill image can't inflate the ZStack it
            // lives in (unframed scaledToFill reports its full aspect size, which
            // once pushed GeometryReader past the 600pt tablet breakpoint).
            if let station = store.current, let image = Artwork.image(for: station) {
                Color.clear
                    .overlay(
                        Image(uiImage: image)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFill()
                    )
                    .clipped()
                    .blur(radius: 90)
                    .opacity(0.28)
                    .ignoresSafeArea()
            }
            LinearGradient(colors: [accent.opacity(0.16), .clear],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [accent.opacity(0.22), .clear],
                           center: .center, startRadius: 0, endRadius: 440)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.6), value: store.current?.id)
    }

    /// Station name + the live "Artist — Title" line (no cover/chips) so the
    /// landscape layout can place them beside the cover. Both animate with the
    /// scramble effect when their text changes.
    private var trackInfo: some View {
        VStack(spacing: 16) {
            MorphText(text: store.current?.name ?? "Tap play to start")
                .font(.title.bold())
                .multilineTextAlignment(.center)

            // Reserve both lines so a wrapping title doesn't nudge the layout as
            // tracks change. Plain text — morphing multi-word titles churns too
            // much to read.
            Text(store.nowPlaying?.display.isEmpty == false ? store.nowPlaying!.display : "Nightride FM")
                .font(.body.weight(.medium))
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)
        }
    }

    /// Quick "I love this song" row — search the live track on a streaming
    /// service or copy "Artist — Title". Always present so its height is
    /// reserved (no layout shift); it fades and disables when no track is known.
    private var trackActions: some View {
        let hasTrack = store.nowPlaying?.isEmpty == false
        return HStack(spacing: 8) {
            ForEach(MusicService.allCases) { service in
                ActionChip(label: service.label, accent: accent) {
                    if let track = store.nowPlaying { MusicSearch.open(service, for: track) }
                }
            }
            ActionChip(label: "copy", accent: accent) {
                if let track = store.nowPlaying {
                    MusicSearch.copy(track)
                    showToast()
                }
            }
        }
        .opacity(hasTrack ? 1 : 0)
        .disabled(!hasTrack)
        .allowsHitTesting(hasTrack)
        .animation(.easeInOut(duration: 0.35), value: hasTrack)
    }

    @ViewBuilder
    private func coverView(size: CGFloat) -> some View {
        if let station = store.current, let image = Artwork.image(for: station) {
            ZStack {
                if artFlipped {
                    PixelSpectrum(spectrum: store.spectrum, accent: accent)
                        .transition(.opacity)
                } else {
                    artworkCover(station: station, image: image, size: size)
                        .transition(.opacity)
                }
            }
            .frame(width: size, height: size)
            .overlay(Rectangle().strokeBorder(accent.opacity(0.6), lineWidth: 1))
            // Easter egg: swipe or tap the cover — it flips to a pixel
            // spectrum fed by the live stream.
            .rotation3DEffect(.degrees(artFlipped ? 180 : 0), axis: (0, 1, 0), perspective: 0.6)
            .onTapGesture { flipArtwork() }
            .gesture(DragGesture(minimumDistance: 12).onEnded { _ in flipArtwork() })
        } else {
            Image(systemName: store.isPlaying ? "waveform" : "moon.stars")
                .font(.system(size: min(size * 0.36, 80)))
                .symbolEffect(.variableColor.iterative,
                              options: .repeating,
                              isActive: store.isPlaying)
                .foregroundStyle(accent)
        }
    }

    private func flipArtwork() {
        let spring = Animation.spring(response: 0.55, dampingFraction: 0.8)
        withAnimation(spring) { artFlipped.toggle() }
        store.setVisualizerActive(artFlipped)
    }

    /// The station cover with its blurred artwork glow behind it.
    private func artworkCover(station: Station, image: UIImage, size: CGFloat) -> some View {
        Image(uiImage: image)
            .resizable()
            .interpolation(.none)   // keep the pixel art crisp when scaled
            .scaledToFit()
            .frame(width: size, height: size)
            // Keyed per station so a switch crossfades with a slight settle.
            .id(station.id)
            .transition(.opacity.combined(with: .scale(scale: 1.06)))
            // Blurred duplicate behind the cover: an artwork-sourced glow
            // that recolors itself with every station switch.
            .background(
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .blur(radius: 36)
                    .opacity(0.35)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            )
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
                    // Symbol morph: play ⇄ pause slides between the glyphs.
                    .contentTransition(.symbolEffect(.replace))
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

/// Shared-letter morph animation: when `text` changes, characters that sit at
/// the same index in the old and new text hold still (SpaceWave → DataWave
/// keeps "a…wave"), everything else churns glyphs briefly then resolves —
/// like a signal re-locking. Fast (0.45s) so it reads as a flick, not a show.
private struct MorphText: View {
    let text: String

    @State private var display: String = ""
    @State private var settled = ""

    /// Glyph pool the unresolved characters cycle through.
    private static let glyphs = Array("!<>-_\\/[]{}=+*^?#")

    var body: some View {
        Text(display)
            .task(id: text) { await morph() }
    }

    private func morph() async {
        guard text != settled else { display = text; return }
        let target = Array(text)
        let from = Array(settled)
        let duration = 0.45
        let started = Date()
        while true {
            let progress = Date().timeIntervalSince(started) / duration
            if progress >= 1 {
                display = text
                settled = text
                return
            }
            let frontier = Int(Double(target.count) * progress)
            display = String(target.enumerated().map { i, c in
                // Shared letters hold; unresolved churn; spaces stay spaces.
                if i < from.count, from[i] == c { return c }
                if i < frontier { return c }
                return c == " " ? " " : Self.glyphs.randomElement()!
            })
            try? await Task.sleep(for: .seconds(0.03))
        }
    }
}

/// The easter egg's back face: a pixel-art spectrum. Redrawn every frame via
/// TimelineView reading the engine's snapshot — no published state churns
/// SwiftUI at 60fps, only the Canvas contents change.
private struct PixelSpectrum: View {
    let spectrum: AudioSpectrum
    let accent: Color

    var body: some View {
        TimelineView(.animation) { _ in
            Canvas { ctx, size in
                let levels = spectrum.snapshot()
                let cols = levels.count
                let rows = 8
                let gap: CGFloat = 2
                let cell = min((size.width - gap * CGFloat(cols - 1)) / CGFloat(cols),
                               (size.height - gap * CGFloat(rows - 1)) / CGFloat(rows))
                let gridW = CGFloat(cols) * cell + gap * CGFloat(cols - 1)
                let gridH = CGFloat(rows) * cell + gap * CGFloat(rows - 1)
                let origin = CGPoint(x: (size.width - gridW) / 2, y: (size.height - gridH) / 2)
                for (col, level) in levels.enumerated() {
                    drawColumn(ctx, level: level, col: col, rows: rows,
                               origin: origin, cell: cell, gap: gap, gridH: gridH)
                }
            }
        }
        .background(Color(hex: 0x0E0A12).opacity(0.6))
        .shadow(color: accent.opacity(0.5), radius: 16)
    }

    private func drawColumn(
        _ ctx: GraphicsContext, level: Float, col: Int, rows: Int,
        origin: CGPoint, cell: CGFloat, gap: CGFloat, gridH: CGFloat
    ) {
        let lit = min(rows, Int(level * Float(rows + 1)))
        let x = origin.x + CGFloat(col) * (cell + gap)
        for row in 0..<rows {
            // Row 0 is the bottom of the stack.
            let y = origin.y + gridH - CGFloat(row + 1) * (cell + gap)
            let rect = CGRect(x: x, y: y, width: cell, height: cell)
            if row < lit {
                // Peak cell flashes white, the rest shade with height.
                let top = row == lit - 1
                let shade = accent.opacity(0.55 + 0.45 * Double(row) / Double(rows))
                ctx.fill(Path(rect), with: .color(top ? .white : shade))
            } else {
                ctx.fill(Path(rect), with: .color(.white.opacity(0.06)))
            }
        }
    }
}

/// Horizontal CRT scanline overlay drawn in a single Canvas pass.
private struct Scanlines: View {
    var body: some View {
        Canvas { ctx, size in
            var y: CGFloat = 0
            while y < size.height {
                ctx.fill(
                    Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                    with: .color(.black.opacity(0.16))
                )
                y += 3
            }
        }
        .allowsHitTesting(false)
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

    /// Same persisted key as ContentView — flipping it retints the app live.
    @AppStorage("scanlines") private var scanlinesOn =
        UserDefaults.standard.string(forKey: "theme") == "amber"

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

                // CRT scanlines toggle — flips ContentView live via the shared @AppStorage key.
                Toggle("CRT scanlines", isOn: $scanlinesOn)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .tint(accent)
                    .fixedSize()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)

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
