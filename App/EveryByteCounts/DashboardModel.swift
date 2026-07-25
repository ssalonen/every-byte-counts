import Foundation
import Combine
import SwiftUI
import WidgetKit
import UserNotifications
import MobileDataCore

/// Bridges the SwiftUI app to `MobileDataCore`. The app owns no business logic
/// (design §4) — it samples through the service, publishes the composed report,
/// and forwards any fired alerts to the notification centre.
@MainActor
final class DashboardModel: ObservableObject {
    @Published private(set) var report: UsageReport?
    @Published private(set) var history: [CycleSummary] = []
    @Published var plan: PlanConfig = .default

    /// nil when the shared App Group container can't be resolved at launch. The
    /// container is the app's only persistent storage, so a nil here means the
    /// build is signed without the group.fi.mailhub.everybytecounts entitlement
    /// — a misconfiguration no runtime workaround can fix. Rather than crash, the
    /// app presents a blocking error screen (see `EveryByteCountsApp` /
    /// `StartupErrorView`); every method below no-ops safely while it's nil.
    private let service: MobileDataService?

    /// Whether the live data service is available. `false` means the shared
    /// storage couldn't be opened and the UI should show the startup error
    /// screen instead of the dashboard.
    var isStorageAvailable: Bool { service != nil }

    /// - Parameter service: injected by tests. Production passes nothing and the
    ///   live App Group service is used (nil if the container is unavailable).
    init(service: MobileDataService? = nil) {
        self.service = service ?? MobileDataService.live(appGroupIdentifier: AppConstants.appGroupIdentifier)
        if let service = self.service {
            self.plan = service.currentState().plan
        }
    }

    /// Called when the app foregrounds: sample, post any alerts, refresh UI and
    /// nudge the widget to reload (design §1 sampling moment (a)).
    func onForeground() {
        guard let service else { return }
        if let result = service.sample() {
            postAlerts(result.pendingAlerts)
        }
        refresh()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func refresh() {
        guard let service else { return }
        report = service.report()
        history = service.cycleHistory()
        plan = service.currentState().plan
    }

    func savePlan(_ newPlan: PlanConfig) {
        guard let service else { return }
        service.updatePlan { $0 = newPlan }
        refresh()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Align this cycle's usage with the carrier-reported figure (e.g. after a
    /// mid-cycle install). Returns whether the calibration could be applied.
    @discardableResult
    func calibrate(usedThisCycleGB: Double) -> Bool {
        guard let service else { return false }
        let applied = service.calibrate(usedThisCycle: DataSize(gigabytes: usedThisCycleGB))
        refresh()
        WidgetCenter.shared.reloadAllTimelines()
        return applied
    }

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func postAlerts(_ alerts: [PendingAlert]) {
        let center = UNUserNotificationCenter.current()
        for alert in alerts {
            let content = UNMutableNotificationContent()
            content.title = alert.title
            content.body = alert.body
            content.sound = .default
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            center.add(request)
        }
    }
}
