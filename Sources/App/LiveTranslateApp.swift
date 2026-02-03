import SwiftUI

@available(iOS 18.0, *)
@main
struct LiveTranslateApp: App {
    @StateObject private var coordinator = TranslationCoordinator()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(coordinator)
                .environmentObject(coordinator.configuration)
                .environmentObject(coordinator.subtitleTimeline)
                .onDisappear {
                    coordinator.cleanup()
                }
        }
    }
}
