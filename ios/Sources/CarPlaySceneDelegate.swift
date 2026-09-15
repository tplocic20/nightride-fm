import CarPlay
import Combine
import MediaPlayer
import UIKit

/// CarPlay entry point. Roots on the system `CPNowPlayingTemplate` (one tap to
/// play/resume the last station); the station list hangs off its Up Next button
/// — the floating list button the system draws top-right, same as Apple Music.
/// Playback flows through the phone's `PlayerStore` — no CarPlay-specific glue.
/// Dead weight without the `com.apple.developer.carplay-audio` entitlement (the
/// Simulator doesn't enforce it, so the UI is testable there).
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate,
                                  CPNowPlayingTemplateObserver {
    private var interfaceController: CPInterfaceController?
    /// Rows kept by station id so live metadata can patch them in place rather
    /// than rebuilding the whole template on every feed update.
    private var rows: [String: CPListItem] = [:]
    /// Rendered covers, keyed by station + point size + screen scale. The list
    /// is rebuilt on every Up Next tap; without this that redraws every cover
    /// from the 1024² source each time.
    private var artCache: [String: UIImage] = [:]
    private var cancellables: Set<AnyCancellable> = []

    func templateApplicationScene(
        _ scene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        observeStore()
        // Root = Now Playing, station list one tap away via the Up Next button.
        let template = CPNowPlayingTemplate.shared
        template.isUpNextButtonEnabled = true
        template.add(self)
        interfaceController.setRootTemplate(template, animated: false, completion: nil)
    }

    func templateApplicationScene(
        _ scene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        cancellables.removeAll()
        rows.removeAll()
        artCache.removeAll()
        CPNowPlayingTemplate.shared.remove(self)
        self.interfaceController = nil
    }

    // MARK: – Station list

    func nowPlayingTemplateUpNextButtonTapped(_ nowPlayingTemplate: CPNowPlayingTemplate) {
        guard let controller = interfaceController,
              controller.topTemplate === CPNowPlayingTemplate.shared else { return }
        controller.pushTemplate(makeStationList(), animated: true, completion: nil)
    }

    private func makeStationList() -> CPListTemplate {
        let sections: [CPListSection] = Stations.grouped
            .filter { !$0.stations.isEmpty }
            .map { group in
                let items: [any CPListTemplateItem] =
                    [coverRow(for: group.stations)].compactMap { $0 } + group.stations.map(makeRow)
                return CPListSection(items: items, header: group.title, sectionIndexTitle: nil)
            }
        let template = CPListTemplate(title: "Nightride", sections: sections)
        template.tabImage = UIImage(systemName: "waveform")
        return template
    }

    private func makeRow(for station: Station) -> CPListItem {
        let item = CPListItem(text: station.name,
                              detailText: subtitle(for: station),
                              image: art(for: station, side: 96))
        item.isPlaying = isLive(station)
        item.handler = { [weak self] _, completion in
            Task { @MainActor in
                PlayerStore.shared.play(station)
                // List lives on top of the Now Playing root — pop back to it.
                self?.interfaceController?.popTemplate(animated: true, completion: nil)
                completion()
            }
        }
        rows[station.id] = item
        return item
    }

    /// A horizontally scrolling strip of station covers above the text rows —
    /// the pixel art picks out a station far faster than reading names does.
    /// Art only: the rows right underneath carry the name, the live track and
    /// the now-playing indicator, so nothing here goes stale between taps.
    private func coverRow(for stations: [Station]) -> CPListImageRowItem? {
        // Pair each station with its cover, so a missing asset drops the cell
        // and its tap target together — `listImageRowHandler` indexes by
        // position, and a hole would play the wrong station.
        let cards: [(station: Station, art: UIImage)] = stations.compactMap { station in
            art(for: station, side: coverSide).map { (station, $0) }
        }
        guard !cards.isEmpty else { return nil }

        let item: CPListImageRowItem
        if #available(iOS 26.0, *) {
            // Grid elements are image-only — no card title to truncate to
            // "Chillsy…", no tint fighting the art for contrast — and they draw
            // at more than twice a card's size. The covers already spell the
            // station name in pixel art, and the rows below repeat it in text.
            item = CPListImageRowItem(
                text: nil,
                gridElements: cards.map { card in
                    let element = CPListImageRowItemGridElement(image: card.art)
                    if #available(iOS 26.4, *) {
                        // Image-only cells are silent to VoiceOver otherwise.
                        element.accessibilityLabel = card.station.name
                    }
                    return element
                },
                allowsMultipleLines: false)
        } else {
            item = legacyCoverRow(cards.map(\.art))
        }
        item.listImageRowHandler = { [weak self] _, index, completion in
            // CarPlay may show fewer cards than we hand it, so treat the index
            // as untrusted rather than trapping mid-drive on a bad subscript.
            guard cards.indices.contains(index) else { completion(); return }
            Task { @MainActor in
                PlayerStore.shared.play(cards[index].station)
                self?.interfaceController?.popTemplate(animated: true, completion: nil)
                completion()
            }
        }
        return item
    }

    /// CarPlay resizes anything that doesn't match the expected size, which
    /// would undo the crisp downscale below — so ask for the exact figure.
    private var coverSide: CGFloat {
        if #available(iOS 26.0, *) { return CPListImageRowItemGridElement.maximumImageSize.width }
        return CPListImageRowItem.maximumImageSize.width
    }

    /// iOS 25 and earlier: the same strip at 95pt, via an initialiser whose
    /// header text isn't nullable — hence the empty string. Deprecated under
    /// the iOS 26 SDK; marking this wrapper deprecated is what keeps the
    /// warning from leaking into every build.
    @available(iOS, deprecated: 26.0, message: "Superseded by grid elements.")
    private func legacyCoverRow(_ images: [UIImage]) -> CPListImageRowItem {
        CPListImageRowItem(text: "", images: images)
    }

    /// A small, crisp rendering of the station cover. CarPlay smooth-scales
    /// images, which blurs the pixel art (the 1024² source is also wastefully
    /// large to hand the car), so pre-render a nearest-neighbour downscale —
    /// matching the phone UI's `.interpolation(.none)`.
    ///
    /// Rendered at the *car* screen's scale, not the phone's: a 3x phone
    /// feeding a 2x head unit hands over more pixels than asked for, and
    /// CarPlay resamples them smoothly — undoing the whole point of this.
    private func art(for station: Station, side: CGFloat) -> UIImage? {
        let format = UIGraphicsImageRendererFormat.preferred()
        // Falls back to this device's scale when CarPlay hasn't reported the
        // car's yet — `preferred()` already carries it.
        if let carScale = interfaceController?.carTraitCollection.displayScale, carScale > 0 {
            format.scale = carScale
        }
        let key = "\(station.id)@\(side)@\(format.scale)"
        if let cached = artCache[key] { return cached }
        guard let source = Artwork.image(for: station) else { return nil }
        let size = CGSize(width: side, height: side)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            ctx.cgContext.interpolationQuality = .none
            source.draw(in: CGRect(origin: .zero, size: size))
        }
        artCache[key] = image
        return image
    }

    /// Patch each row's subtitle + now-playing indicator in place whenever the
    /// live station, play/pause state, or any station's metadata changes.
    private func refreshRows() {
        for station in Stations.all {
            guard let item = rows[station.id] else { continue }
            item.setDetailText(subtitle(for: station))
            item.isPlaying = isLive(station)
        }
    }

    /// The live "Artist — Title" for a station, or the network name as a resting
    /// subtitle before any track is known.
    private func subtitle(for station: Station) -> String {
        let track = PlayerStore.shared.latestMeta[station.id]
        return (track?.isEmpty == false) ? track!.display : "Nightride FM"
    }

    private func isLive(_ station: Station) -> Bool {
        let store = PlayerStore.shared
        return store.current?.id == station.id && store.isPlaying
    }

    // MARK: – Store observation

    private func observeStore() {
        // `objectWillChange` fires before the values settle — hop a turn to read.
        PlayerStore.shared.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in self?.refreshRows() }
            }
            .store(in: &cancellables)
    }
}
