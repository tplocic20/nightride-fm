import SwiftUI
import UIKit

@main
struct NightrideApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = PlayerStore.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if connectingSceneSession.role == .carTemplateApplication {
            let cfg = UISceneConfiguration(name: "CarPlay Configuration",
                                           sessionRole: .carTemplateApplication)
            cfg.delegateClass = CarPlaySceneDelegate.self
            return cfg
        }
        // SwiftUI's WindowGroup handles the standard iPhone/iPad scene itself.
        return UISceneConfiguration(name: "Default Configuration",
                                    sessionRole: connectingSceneSession.role)
    }
}
