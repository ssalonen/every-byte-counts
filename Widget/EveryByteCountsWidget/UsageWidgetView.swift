import WidgetKit
import SwiftUI
import MobileDataCore

/// Renders the glance for every supported family — Home Screen (small/medium) and
/// Lock Screen (circular/rectangular). Design §2.
struct UsageWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: UsageEntry

    private var tint: Color {
        switch entry.status {
        case .safe: return .green
        case .atRisk: return .orange
        case .over: return .red
        }
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: min(1, entry.fractionUsed)) {
                Image(systemName: "antenna.radiowaves.left.and.right")
            } currentValueLabel: {
                Text(Formatters.percent(entry.fractionUsed))
            }
            .gaugeStyle(.accessoryCircular)
            .tint(tint)

        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Text("\(Formatters.data(entry.remaining)) left").font(.headline)
                Text("\(entry.daysRemaining) days · \(Formatters.percent(entry.fractionUsed)) used")
                    .font(.caption)
            }

        default:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "antenna.radiowaves.left.and.right").foregroundStyle(tint)
                    Text("Cellular").font(.caption.bold()).foregroundStyle(.secondary)
                    Spacer()
                }
                Text(Formatters.data(entry.remaining))
                    .font(.system(.title, design: .rounded).bold())
                    .minimumScaleFactor(0.6)
                Text("of \(Formatters.data(entry.cap)) left").font(.caption).foregroundStyle(.secondary)
                ProgressView(value: min(1, entry.fractionUsed)).tint(tint)
                Text("\(entry.daysRemaining) days left in cycle")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
