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
    @State private var carrierUsedGB: Double = 0
    @State private var didCalibrate = false
    @State private var enabledThresholds: Set<Double> = []
    @State private var justSaved = false

    /// Standard thresholds plus anything already in the plan, so a custom value
    /// persisted earlier still shows up as a toggleable row.
    private var thresholdOptions: [Double] {
        Set([0.5, 0.8, 1.0]).union(model.plan.alertThresholds).sorted()
    }

    var body: some View {
        NavigationStack {
            Form {
                if model.storageUnavailable {
                    Section {
                        Label("Shared storage is unavailable, so these settings can't be saved — they will reset when the app closes. This build may be missing its App Group entitlement; please report it.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

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

                Section("Calibrate this cycle") {
                    HStack {
                        Text("Used so far")
                        Spacer()
                        TextField("GB", value: $carrierUsedGB, format: .number.precision(.fractionLength(0...2)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 100)
                        Text("GB").foregroundStyle(.secondary)
                    }
                    Button(didCalibrate ? "Calibrated ✓" : "Calibrate") {
                        didCalibrate = model.calibrate(usedThisCycleGB: max(0, carrierUsedGB))
                    }
                    Text("Installed mid-cycle? Enter the usage your carrier reports for the current cycle and tracking continues from there — no need to wait for the next cycle. Applies to this cycle only.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Alerts") {
                    ForEach(thresholdOptions, id: \.self) { t in
                        Toggle("Notify at \(Int(t * 100))%", isOn: thresholdBinding(for: t))
                    }
                }

                Section {
                    Button {
                        save()
                    } label: {
                        // Full-width label so the whole row is tappable, not
                        // just the text.
                        Label(justSaved ? "Saved" : "Save",
                              systemImage: justSaved ? "checkmark" : "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                    }
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
        // Pre-fill with the app's current figure so the user only nudges it to
        // match the carrier's.
        carrierUsedGB = model.report?.summary.used.gigabytes ?? 0
        didCalibrate = false
        enabledThresholds = Set(model.plan.alertThresholds)
    }

    private func thresholdBinding(for threshold: Double) -> Binding<Bool> {
        Binding(
            get: { enabledThresholds.contains(threshold) },
            set: { enabled in
                if enabled {
                    enabledThresholds.insert(threshold)
                } else {
                    enabledThresholds.remove(threshold)
                }
            }
        )
    }

    private func save() {
        var plan = model.plan
        plan.capGB = capGB
        plan.cycleResetDay = resetDay
        plan.costModel = .flatRate(eurPerGB: eurPerGB)
        plan.alertThresholds = enabledThresholds.sorted()
        model.savePlan(plan)

        withAnimation { justSaved = true }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { justSaved = false }
        }
    }
}
