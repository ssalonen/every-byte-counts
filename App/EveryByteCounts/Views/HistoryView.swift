import SwiftUI
import Charts
import MobileDataCore

/// Day-by-day (current cycle) and month-by-month (closed cycles) history
/// (design §2).
struct HistoryView: View {
    @EnvironmentObject var model: DashboardModel

    var body: some View {
        NavigationStack {
            List {
                Section("This cycle — daily") {
                    if let daily = model.report?.dailyTotals, !daily.isEmpty {
                        DailyChart(totals: daily)
                            .frame(height: 200)
                            .listRowInsets(EdgeInsets())
                            .padding()
                    } else {
                        Text("No usage recorded yet.").foregroundStyle(.secondary)
                    }
                }

                Section("Past cycles") {
                    if model.history.isEmpty {
                        Text("History accumulates from install onward.")
                            .foregroundStyle(.secondary)
                    } else {
                        MonthlyChart(cycles: model.history)
                            .frame(height: 180)
                            .listRowInsets(EdgeInsets())
                            .padding()
                        ForEach(model.history) { cycle in
                            NavigationLink {
                                CycleDetailView(cycle: cycle)
                            } label: {
                                CycleRow(cycle: cycle)
                            }
                        }
                    }
                }
            }
            .navigationTitle("History")
        }
    }
}

private struct DailyChart: View {
    let totals: [DailyTotal]
    var body: some View {
        Chart(totals) { day in
            BarMark(
                x: .value("Day", day.date, unit: .day),
                y: .value("GB", day.cellular.gigabytes)
            )
            .foregroundStyle(.blue)
        }
        .chartYAxisLabel("GB")
    }
}

private struct MonthlyChart: View {
    let cycles: [CycleSummary]
    var body: some View {
        Chart(cycles) { cycle in
            BarMark(
                x: .value("Cycle", cycle.start, unit: .month),
                y: .value("GB", cycle.total.gigabytes)
            )
            .foregroundStyle(cycle.overageGB > 0 ? .red : .blue)
        }
        .chartYAxisLabel("GB")
    }
}

private struct CycleRow: View {
    let cycle: CycleSummary
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(cycle.start, format: .dateTime.month(.wide).year())
                Text("Cap \(Formatters.gigabytes(cycle.capGB))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(Formatters.data(cycle.total)).bold()
                if cycle.overageGB > 0 {
                    Text("+\(Formatters.euros(cycle.estimatedCostEUR))")
                        .font(.caption).foregroundStyle(.red)
                }
            }
        }
    }
}

private struct CycleDetailView: View {
    let cycle: CycleSummary
    var body: some View {
        List {
            LabeledContent("Total used", value: Formatters.data(cycle.total))
            LabeledContent("Cap", value: Formatters.gigabytes(cycle.capGB))
            LabeledContent("Overage", value: Formatters.gigabytes(cycle.overageGB))
            LabeledContent("Estimated cost", value: Formatters.euros(cycle.estimatedCostEUR))
            LabeledContent("Cycle start", value: cycle.start.formatted(date: .abbreviated, time: .omitted))
            LabeledContent("Cycle end", value: cycle.end.formatted(date: .abbreviated, time: .omitted))
        }
        .navigationTitle(cycle.start.formatted(.dateTime.month(.wide).year()))
    }
}
