import SwiftUI
import MobileDataCore

@main
struct EveryByteCountsApp: App {
    @StateObject private var model = DashboardModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
        }
        // Sampling moment (a) from design §1: take a sample whenever the app
        // becomes active (cold launch and every return to foreground).
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.onForeground() }
        }
    }
}
