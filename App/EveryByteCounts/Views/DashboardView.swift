import SwiftUI
import Charts
import MobileDataCore

/// The headline dashboard (design §2): used / remaining / % / days left, the
/// recency-weighted daily budget, the projection + status, and the overage cost.
struct DashboardView: View {
    @EnvironmentObject var model: DashboardModel

    var body: some View {
        NavigationStack {
            ScrollView {
                if let report = model.report {
                    VStack(spacing: 20) {
                        RemainingRing(summary: report.summary)
                        ForecastCard(forecast: report.forecast)
                        CumulativeCard(report: report)
                        StatsGrid(summary: report.summary)
                        EstimateDisclaimer()
                    }
                    .padding()
                } else {
                    ProgressView().padding(.top, 80)
                }
            }
            .navigationTitle("Cellular Data")
            .refreshable { model.onForeground() }
        }
    }
}

/// Circular remaining-data gauge with % consumed in the centre.
private struct RemainingRing: View {
    let summary: UsageSummary

    private var color: Color {
        switch summary.fractionUsed {
        case ..<0.8: return .green
        case ..<1.0: return .orange
        default: return .red
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().stroke(Color.gray.opacity(0.2), lineWidth: 16)
                Circle()
                    .trim(from: 0, to: min(1, summary.fractionUsed))
                    .stroke(color, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack {
                    Text(Formatters.percent(summary.fractionUsed))
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                    Text("used").foregroundStyle(.secondary)
                }
            }
            .frame(width: 200, height: 200)

            Text("\(Formatters.data(summary.remaining)) remaining of \(Formatters.data(summary.cap))")
                .font(.headline)
        }
    }
}

private struct ForecastCard: View {
    let forecast: Forecast

    private var statusColor: Color {
        switch forecast.status {
        case .safe: return .green
        case .atRisk: return .orange
        case .over: return .red
        }
    }

    private var statusText: String {
        switch forecast.status {
        case .safe: return "On track"
        case .atRisk: return "At risk"
        case .over: return "Projected over"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                Text("Forecast").font(.headline)
                Spacer()
                Text(statusText)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(statusColor, in: Capsule())
            }
            Text("You can use \(Formatters.gigabytes(forecast.remainingDailyBudgetGB))/day and stay under the cap.")
                .fontWeight(.medium)
            Text("Projected end of cycle: \(Formatters.gigabytes(forecast.projectedTotalGB))")
                .foregroundStyle(.secondary).font(.subheadline)
            if forecast.projectedExcessGB > 0 {
                Divider()
                Text("Estimated overage: \(Formatters.euros(forecast.overageCostEUR))")
                    .font(.subheadline.bold()).foregroundStyle(.red)
                Text(forecast.overageBasis).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Cumulative usage over the cycle with the forecast projection continued to
/// cycle end as a dashed line in the status colour, against the cap line —
/// the "where is this heading" picture behind the ForecastCard numbers.
private struct CumulativeCard: View {
    private let summary: UsageSummary
    private let series: CumulativeUsageSeries

    init(report: UsageReport) {
        self.summary = report.summary
        self.series = CumulativeUsageSeries(report: report)
    }

    private var statusColor: Color {
        switch series.status {
        case .safe: return .green
        case .atRisk: return .orange
        case .over: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "chart.xyaxis.line")
                Text("Cycle so far").font(.headline)
            }

            Chart {
                ForEach(series.actual) { point in
                    AreaMark(
                        x: .value("Day", point.date),
                        y: .value("GB", point.gigabytes)
                    )
                    .foregroundStyle(.blue.opacity(0.12))
                }
                ForEach(series.actual) { point in
                    LineMark(
                        x: .value("Day", point.date),
                        y: .value("GB", point.gigabytes),
                        series: .value("Series", "Used")
                    )
                    .foregroundStyle(by: .value("Series", "Used"))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
                ForEach(series.projected) { point in
                    LineMark(
                        x: .value("Day", point.date),
                        y: .value("GB", point.gigabytes),
                        series: .value("Series", "Projected")
                    )
                    .foregroundStyle(by: .value("Series", "Projected"))
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 4]))
                }
                if let end = series.projected.last {
                    PointMark(
                        x: .value("Day", end.date),
                        y: .value("GB", end.gigabytes)
                    )
                    .foregroundStyle(statusColor)
                    .annotation(position: .leading, alignment: .trailing) {
                        Text("Projected \(Formatters.gigabytes(end.gigabytes))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                RuleMark(y: .value("Cap", series.capGB))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .topLeading) {
                        Text("Cap \(Formatters.gigabytes(series.capGB))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
            }
            .chartXScale(domain: summary.cycleStart...summary.cycleEnd)
            .chartForegroundStyleScale(["Used": Color.blue, "Projected": statusColor])
            .chartYAxisLabel("GB")
            .frame(height: 220)
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct StatsGrid: View {
    let summary: UsageSummary
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            StatTile(title: "Used", value: Formatters.data(summary.used))
            StatTile(title: "Remaining", value: Formatters.data(summary.remaining))
            StatTile(title: "Days left", value: "\(summary.daysRemaining)")
            StatTile(title: "Day \(summary.daysElapsed)", value: "of cycle")
        }
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.title2.bold())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct EstimateDisclaimer: View {
    var body: some View {
        Text("Figures are an on-device estimate from system counters and may differ a few percent from your carrier's billing.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }
}
