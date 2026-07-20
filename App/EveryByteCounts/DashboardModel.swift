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

    private let service: MobileDataService

    /// - Parameter service: injected by tests. Production passes nothing and the
    ///   live App Group service is used.
    init(service: MobileDataService? = nil) {
        if let service {
            self.service = service
        } else if let live = MobileDataService.live(appGroupIdentifier: AppConstants.appGroupIdentifier) {
            self.service = live
        } else {
            // The App Group container is the app's only persistent storage. A nil
            // here means the build is signed without the
            // group.fi.mailhub.everybytecounts entitlement — a misconfiguration
            // no runtime workaround can fix, so fail loudly at startup rather
            // than run in a state that can only lose data. The release
            // pipeline's entitlement check is meant to catch this even earlier.
            fatalError("""
                App Group '\(AppConstants.appGroupIdentifier)' is unavailable. \
                The app is signed without its App Group entitlement, so there is \
                no persistent storage. Enable the App Groups capability for both \
                bundle IDs in the Developer portal and re-sign.
                """)
        }
        self.plan = self.service.currentState().plan
    }

    /// Called when the app foregrounds: sample, post any alerts, refresh UI and
    /// nudge the widget to reload (design §1 sampling moment (a)).
    func onForeground() {
        if let result = service.sample() {
            postAlerts(result.pendingAlerts)
        }
        refresh()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func refresh() {
        report = service.report()
        history = service.cycleHistory()
        plan = service.currentState().plan
    }

    func savePlan(_ newPlan: PlanConfig) {
        service.updatePlan { $0 = newPlan }
        refresh()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Align this cycle's usage with the carrier-reported figure (e.g. after a
    /// mid-cycle install). Returns whether the calibration could be applied.
    @discardableResult
    func calibrate(usedThisCycleGB: Double) -> Bool {
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
