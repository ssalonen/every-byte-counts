import SwiftUI
import MobileDataCore

@main
struct EveryByteCountsApp: App {
    @StateObject private var model = DashboardModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            if model.isStorageAvailable {
                RootView()
                    .environmentObject(model)
            } else {
                // The shared App Group container couldn't be opened, so there's
                // no persistent storage. Present a blocking explanation instead
                // of running in a data-losing state (or crashing).
                StartupErrorView(appGroupIdentifier: AppConstants.appGroupIdentifier)
            }
        }
        // Sampling moment (a) from design §1: take a sample whenever the app
        // becomes active (cold launch and every return to foreground).
        // onForeground no-ops when storage is unavailable.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.onForeground() }
        }
    }
}
