import WidgetKit
import SwiftUI
import MobileDataCore

/// Timeline entry carrying the glance figures.
struct UsageEntry: TimelineEntry {
    let date: Date
    let remaining: DataSize
    let cap: DataSize
    let fractionUsed: Double
    let usedToday: DataSize
    let daysRemaining: Int
    let status: ForecastStatus

    static let placeholder = UsageEntry(
        date: Date(),
        remaining: DataSize(gigabytes: 12.7),
        cap: DataSize(gigabytes: 20),
        fractionUsed: 0.365,
        usedToday: DataSize(gigabytes: 0.48),
        daysRemaining: 14,
        status: .safe
    )
}

/// The widget is a *core sampling mechanism*, not just a display surface (design
/// §1/§4): every timeline refresh takes a sample through the shared service
/// before building the entry, which is how usage is captured while the app is
/// closed. Sampling is idempotent and cheap, so doing it here is safe.
struct UsageProvider: TimelineProvider {
    private func makeService() -> MobileDataService? {
        MobileDataService.live(appGroupIdentifier: AppConstants.appGroupIdentifier)
    }

    func placeholder(in context: Context) -> UsageEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        completion(entry(sampling: !context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let entry = entry(sampling: true)
        // Ask WidgetKit to refresh in ~30 min; this both updates the glance and
        // is the background sampling heartbeat. App-launch sampling backstops the
        // (system-throttled) actual cadence — see design §7.
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func entry(sampling: Bool) -> UsageEntry {
        guard let service = makeService() else { return .placeholder }
        if sampling { service.sample() } // the heartbeat
        let report = service.report()
        return UsageEntry(
            date: Date(),
            remaining: report.summary.remaining,
            cap: report.summary.cap,
            fractionUsed: report.summary.fractionUsed,
            usedToday: report.usedToday,
            daysRemaining: report.summary.daysRemaining,
            status: report.forecast.status
        )
    }
}

struct EveryByteCountsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: AppConstants.widgetKind, provider: UsageProvider()) { entry in
            UsageWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Data Remaining")
        .description("Cellular data left this cycle.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}
