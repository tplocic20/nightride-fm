import CarPlay
import MediaPlayer
import UIKit

/// CarPlay entry point. Builds a CPListTemplate of stations, then pushes
/// CPNowPlayingTemplate when one is selected. The Now Playing template is
/// driven by the same MPNowPlayingInfoCenter / MPRemoteCommandCenter that
/// the iPhone UI uses — so play/pause/next/prev work in the car with no
/// CarPlay-specific glue.
///
/// This whole file is dead code on builds without the
/// `com.apple.developer.carplay-audio` entitlement; iOS just never tries
/// to connect a CarPlay scene without it.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?

    func templateApplicationScene(
        _ scene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        let root = makeStationList()
        interfaceController.setRootTemplate(root, animated: false, completion: nil)
    }

    func templateApplicationScene(
        _ scene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        self.interfaceController = nil
    }

    // MARK: – Templates

    private func makeStationList() -> CPListTemplate {
        let items: [CPListItem] = Stations.all.map { station in
            let item = CPListItem(text: station.name, detailText: "Nightride FM")
            item.handler = { [weak self] _, completion in
                Task { @MainActor in
                    PlayerStore.shared.play(station)
                }
                self?.pushNowPlaying()
                completion()
            }
            return item
        }
        let section = CPListSection(items: items)
        let template = CPListTemplate(title: "Nightride", sections: [section])
        template.tabImage = UIImage(systemName: "waveform")
        return template
    }

    private func pushNowPlaying() {
        guard let controller = interfaceController else { return }
        let template = CPNowPlayingTemplate.shared
        // Avoid stacking duplicates if user taps a station twice.
        if controller.topTemplate === template { return }
        controller.pushTemplate(template, animated: true, completion: nil)
    }
}
