import SwiftUI
import MobileDataCore

/// Plan configuration (design §2): cap, cycle reset day, flat €/GB rate and the
/// threshold alerts. Bound to the cost-model *abstraction* via a simple editor so
/// richer models can be exposed later without reworking this screen (design §5).
struct SettingsView: View {
    @EnvironmentObject var model: DashboardModel

    @State private var capGB: Double = 20
    @State private var resetDay: Int = 1
    @State private var eurPerGB: Double = 5

    var body: some View {
        NavigationStack {
            Form {
                Section("Monthly plan") {
                    Stepper(value: $capGB, in: 1...500, step: 1) {
                        Text("Cap: \(Formatters.gigabytes(capGB))")
                    }
                    Picker("Resets on day", selection: $resetDay) {
                        ForEach(1...31, id: \.self) { Text("\($0)") }
                    }
                }

                Section("Overage cost") {
                    Stepper(value: $eurPerGB, in: 0...100, step: 0.5) {
                        Text("Rate: \(Formatters.euros(eurPerGB))/GB")
                    }
                    Text("Flat €/GB on data over the cap.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Alerts") {
                    ForEach(model.plan.alertThresholds, id: \.self) { t in
                        Text("Notify at \(Int(t * 100))%")
                    }
                }

                Section {
                    Button("Save") { save() }
                }

                Section {
                    Text("Tracks the whole-device cellular counter. Per-app and hotspot usage can't be separated on iOS.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .onAppear(perform: loadFromPlan)
        }
    }

    private func loadFromPlan() {
        capGB = model.plan.capGB
        resetDay = model.plan.cycleResetDay
        if case let .flatRate(rate) = model.plan.costModel { eurPerGB = rate }
    }

    private func save() {
        var plan = model.plan
        plan.capGB = capGB
        plan.cycleResetDay = resetDay
        plan.costModel = .flatRate(eurPerGB: eurPerGB)
        model.savePlan(plan)
    }
}
