import CarPlay
import Combine
import MediaPlayer
import UIKit

/// CarPlay entry point. Presents a `CPListTemplate` of stations — each row shows
/// the station's current live track and a now-playing indicator for the active
/// one — and pushes the system `CPNowPlayingTemplate` when a station is picked.
/// Playback, metadata and transport all flow through the same `PlayerStore` /
/// `MPNowPlayingInfoCenter` / `MPRemoteCommandCenter` the phone UI uses, so
/// there's no CarPlay-specific playback glue.
///
/// This is dead weight on builds without the `com.apple.developer.carplay-audio`
/// entitlement — iOS simply never connects a CarPlay scene without it. (The iOS
/// Simulator does NOT enforce the entitlement, so the whole UI is testable there
/// via I/O → External Displays → CarPlay.)
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
        interfaceController.setRootTemplate(makeStationList(), animated: false, completion: nil)
        observeStore()
        // Already playing when the car connects → jump straight to Now Playing.
        if PlayerStore.shared.isPlaying {
            pushNowPlaying(animated: false)
        }
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

    private func makeStationList() -> CPListTemplate {
        let items: [CPListItem] = Stations.all.map { station in
            let item = CPListItem(text: station.name,
                                  detailText: subtitle(for: station),
                                  image: Artwork.image(for: station))
            item.isPlaying = isLive(station)
            item.handler = { [weak self] _, completion in
                Task { @MainActor in
                    PlayerStore.shared.play(station)
                    self?.pushNowPlaying(animated: true)
                    completion()
                }
            }
            rows[station.id] = item
            return item
        }
        let template = CPListTemplate(title: "Nightride", sections: [CPListSection(items: items)])
        template.tabImage = UIImage(systemName: "waveform")
        return template
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

    // MARK: – Now Playing

    private func pushNowPlaying(animated: Bool) {
        guard let controller = interfaceController else { return }
        let template = CPNowPlayingTemplate.shared
        guard controller.topTemplate !== template else { return }  // don't stack dupes
        controller.pushTemplate(template, animated: animated, completion: nil)
    }

    // MARK: – Store observation

    private func observeStore() {
        // Any published change (current station, play state, or the per-station
        // metadata feed) repaints the rows. `objectWillChange` fires *before* the
        // value updates, so hop a turn to read the settled values.
        PlayerStore.shared.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in self?.refreshRows() }
            }
            .store(in: &cancellables)
    }
}
