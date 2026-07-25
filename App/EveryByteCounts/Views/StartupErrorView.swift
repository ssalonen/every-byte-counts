import SwiftUI

/// Shown at launch when the shared App Group container can't be resolved. The
/// container is the app's only persistent storage, so this state means the
/// build is misconfigured (typically signed without the App Group entitlement)
/// and there's no runtime recovery. Rather than crash, we explain the problem
/// and offer the only safe action: close the app.
struct StartupErrorView: View {
    /// The App Group that couldn't be opened, surfaced so a tester can report
    /// exactly what failed.
    let appGroupIdentifier: String

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 56))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            Text("Storage Unavailable")
                .font(.title2.weight(.bold))

            Text("""
                Every Byte Counts can't open its shared storage, so it can't \
                track your data usage. This is a problem with this build's \
                configuration, not something you can fix on your device.
                """)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("App Group “\(appGroupIdentifier)” could not be opened.")
                .font(.footnote.monospaced())
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Button(role: .destructive) {
                // iOS has no public API to gracefully quit, and there's nothing
                // to retry — the container will stay unavailable for this build.
                // exit(0) is a clean termination (not a crash report) and gives
                // the user the single action they asked for.
                exit(0)
            } label: {
                Text("Close App")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(32)
    }
}
