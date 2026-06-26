import SwiftUI

struct RootView: View {
    @EnvironmentObject var model: DashboardModel

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Usage", systemImage: "gauge.with.dots.needle.bottom.50percent") }
            HistoryView()
                .tabItem { Label("History", systemImage: "chart.bar.fill") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .onAppear { model.requestNotificationPermission() }
    }
}
