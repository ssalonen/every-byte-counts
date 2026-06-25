import Foundation

/// The complete persisted state shared between the app and the widget through the
/// App Group container (design §4). Kept deliberately small and `Codable` so the
/// MVP can use a plain JSON file; the `DataStore` protocol lets this be swapped
/// for SQLite/GRDB later without touching call sites.
public struct AppState: Equatable, Codable, Sendable {
    public var plan: PlanConfig
    public var installDate: Date?

    /// Raw samples, oldest first. Pruned to the retention window by the engine so
    /// the file stays small; closed cycles keep their own aggregate totals.
    public var snapshots: [Snapshot]

    /// The open billing cycle, if one has been started.
    public var currentCycle: Cycle?

    /// Closed cycles, oldest first — the month-by-month history.
    public var closedCycles: [Cycle]

    public var alertState: AlertState

    public init(
        plan: PlanConfig = .default,
        installDate: Date? = nil,
        snapshots: [Snapshot] = [],
        currentCycle: Cycle? = nil,
        closedCycles: [Cycle] = [],
        alertState: AlertState = .empty
    ) {
        self.plan = plan
        self.installDate = installDate
        self.snapshots = snapshots
        self.currentCycle = currentCycle
        self.closedCycles = closedCycles
        self.alertState = alertState
    }

    /// Most recent snapshot, if any.
    public var latestSnapshot: Snapshot? { snapshots.last }
}
