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

    /// True when the App Group container could not be opened and the app is
    /// running on a throwaway in-memory store: everything *appears* to work but
    /// nothing survives the process. Surfaced as a banner so a build signed
    /// without the App Group entitlement can't masquerade as healthy.
    @Published private(set) var storageUnavailable = false

    private let service: MobileDataService

    init(service: MobileDataService? = nil) {
        // Fall back to an in-memory service if the App Group isn't configured yet
        // (e.g. SwiftUI previews), so the UI always has something to render.
        if let service {
            self.service = service
        } else if let live = MobileDataService.live(appGroupIdentifier: AppConstants.appGroupIdentifier) {
            self.service = live
        } else {
            self.service = MobileDataService(store: InMemoryDataStore(), reader: PreviewCounterReader())
            storageUnavailable = true
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

/// Deterministic reader for previews so the UI shows believable numbers without
/// the live counters.
private struct PreviewCounterReader: CounterReader {
    func read() throws -> CounterReading {
        CounterReading(cellular: DataSize(gigabytes: 7.3), wifi: DataSize(gigabytes: 40))
    }
}
