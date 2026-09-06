import CarPlay
import Combine
import MediaPlayer
import UIKit

/// CarPlay entry point. Roots on the system `CPNowPlayingTemplate` (one tap to
/// play/resume the last station) with a trailing nav-bar button that pushes the
/// station list. Playback flows through the phone's `PlayerStore` — no
/// CarPlay-specific glue. Dead weight without the
/// `com.apple.developer.carplay-audio` entitlement (the Simulator doesn't
/// enforce it, so the UI is testable there).
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?
    /// Rows kept by station id so live metadata can patch them in place rather
    /// than rebuilding the whole template on every feed update.
    private var rows: [String: CPListItem] = [:]
    private var cancellables: Set<AnyCancellable> = []

    func templateApplicationScene(
        _ scene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        observeStore()
        // Root = Now Playing, station list one tap away via a custom button
        // (CPNowPlayingTemplate has no nav-bar corner buttons, so the button
        // joins the playback control row instead).
        CPNowPlayingTemplate.shared.updateNowPlayingButtons([makeStationListButton()])
        interfaceController.setRootTemplate(CPNowPlayingTemplate.shared, animated: false, completion: nil)
    }

    func templateApplicationScene(
        _ scene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        cancellables.removeAll()
        rows.removeAll()
        self.interfaceController = nil
    }

    // MARK: – Station list

    /// Custom button in the Now Playing control row that pushes the station list.
    private func makeStationListButton() -> CPNowPlayingImageButton {
        let config = UIImage.SymbolConfiguration(pointSize: 24, weight: .medium)
        guard let image = UIImage(systemName: "list.bullet", withConfiguration: config)?
            .applyingSymbolConfiguration(.init(paletteColors: [.white]))
        else { fatalError("missing list.bullet symbol") }
        return CPNowPlayingImageButton(image: image) { [weak self] _ in
            guard let self, let controller = self.interfaceController,
                  controller.topTemplate !== CPNowPlayingTemplate.shared else { return }
            controller.pushTemplate(self.makeStationList(), animated: true, completion: nil)
        }
    }

    private func makeStationList() -> CPListTemplate {
        let sections: [CPListSection] = Stations.grouped
            .filter { !$0.stations.isEmpty }
            .map { group in
                let items = group.stations.map(makeRow)
                return CPListSection(items: items, header: group.title, sectionIndexTitle: nil)
            }
        let template = CPListTemplate(title: "Nightride", sections: sections)
        template.tabImage = UIImage(systemName: "waveform")
        return template
    }

    private func makeRow(for station: Station) -> CPListItem {
        let item = CPListItem(text: station.name,
                              detailText: subtitle(for: station),
                              image: rowArt(for: station))
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

    /// A small, crisp thumbnail of the station cover. CarPlay smooth-scales row
    /// images, which blurs the pixel art (the 1024² source is also wastefully
    /// large to hand the car), so pre-render a nearest-neighbour downscale —
    /// matching the phone UI's `.interpolation(.none)`.
    private func rowArt(for station: Station) -> UIImage? {
        guard let source = Artwork.image(for: station) else { return nil }
        let side: CGFloat = 96
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        return renderer.image { ctx in
            ctx.cgContext.interpolationQuality = .none
            source.draw(in: CGRect(origin: .zero, size: CGSize(width: side, height: side)))
        }
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
