import Foundation

/// Converts a raw (since-boot) counter read into a delta to add to the monotonic
/// running total, handling the reboot case (design §1).
///
/// The interface counter resets to zero on reboot, so a *new reading lower than
/// the previous one* means a reboot (or a 32-bit wrap) happened. In that case the
/// new reading is itself the post-reboot delta; the small amount of traffic
/// between the last sample and the reboot can't be recovered and is dropped — the
/// accepted minor inaccuracy from §7.
public enum RebootAdjuster {
    /// - Parameters:
    ///   - previousRaw: the raw counter at the previous sample.
    ///   - currentRaw: the raw counter now.
    /// - Returns: the bytes to add to the cumulative running total, and whether a
    ///   reboot was detected.
    public static func delta(previousRaw: DataSize, currentRaw: DataSize) -> (delta: DataSize, didReboot: Bool) {
        if currentRaw.bytes >= previousRaw.bytes {
            return (DataSize(bytes: currentRaw.bytes - previousRaw.bytes), false)
        } else {
            // Counter went backwards → reboot/wrap. Post-reboot usage is the new
            // reading itself (counted up from zero).
            return (currentRaw, true)
        }
    }
}
