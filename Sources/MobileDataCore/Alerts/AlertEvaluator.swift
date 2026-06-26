import Foundation

/// A notification the app should post.
public struct PendingAlert: Equatable, Sendable {
    /// The threshold fraction that was crossed (e.g. 0.8).
    public var threshold: Double
    public var title: String
    public var body: String

    public init(threshold: Double, title: String, body: String) {
        self.threshold = threshold
        self.title = title
        self.body = body
    }
}

/// Evaluates threshold alerts during sampling (design §4). Fires each threshold
/// at most once per cycle by tracking fired-flags in `AlertState`, and resets
/// that set when the active cycle changes.
public struct AlertEvaluator {
    public init() {}

    /// - Parameters:
    ///   - fractionUsed: usage as a fraction of the cap.
    ///   - thresholds: configured thresholds (fractions of the cap).
    ///   - cycleID: id of the currently active cycle.
    ///   - state: previous alert state.
    /// - Returns: alerts to post now, and the updated state to persist.
    public func evaluate(
        fractionUsed: Double,
        thresholds: [Double],
        cycleID: UUID?,
        state: AlertState
    ) -> (alerts: [PendingAlert], state: AlertState) {
        // A new cycle clears the fired set so thresholds can fire again.
        var fired = state.cycleID == cycleID ? state.firedThresholds : []

        var alerts: [PendingAlert] = []
        for threshold in thresholds.sorted() where fractionUsed >= threshold && !fired.contains(threshold) {
            fired.insert(threshold)
            alerts.append(makeAlert(for: threshold))
        }

        return (alerts, AlertState(cycleID: cycleID, firedThresholds: fired))
    }

    private func makeAlert(for threshold: Double) -> PendingAlert {
        let pct = Int((threshold * 100).rounded())
        if threshold >= 1.0 {
            return PendingAlert(
                threshold: threshold,
                title: "Data cap reached",
                body: "You've used 100% of your monthly cellular data."
            )
        }
        return PendingAlert(
            threshold: threshold,
            title: "Data usage at \(pct)%",
            body: "You've used \(pct)% of your monthly cellular data."
        )
    }
}
