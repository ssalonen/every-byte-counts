import Foundation

/// Converts a raw (since-boot) counter read into the delta to add to the
/// monotonic running total (design §1).
///
/// Three different events make a raw counter fall, and they need opposite
/// treatment:
///
///   * **Reboot** — every counter on the device restarts from zero. The new
///     reading *is* the delta; traffic between the last sample and the reboot
///     can't be recovered and is dropped (the accepted §7 inaccuracy).
///   * **Interface restart** — iOS re-creates `pdp_ip0` on an airplane-mode or
///     cellular-data toggle or a SIM switch, zeroing that one interface's
///     counters mid-boot. Same treatment, one interface at a time.
///   * **32-bit wrap** — `if_data`'s byte counters are `u_int32_t`, so each one
///     rolls over to zero every 4 GiB while the interface keeps running. Here
///     the bytes between the last reading and the wrap point are *real traffic*:
///     the delta is `(2³² − previous) + current`.
///
/// Treating a wrap as a restart is what silently lost up to 4 GiB of usage per
/// wrap — the app under-reporting against the carrier's figure. Telling them
/// apart needs the counters kept per interface and direction (a sum of two
/// independently wrapping counters can fall with nothing having restarted),
/// which is what `deltas(previous:previousBootTime:current:currentBootTime:)`
/// consumes.
public enum RebootAdjuster {

    /// Width of the kernel's 32-bit interface counters — the amount a wrapped
    /// counter has to have the wrap added back.
    public static let counterWidth: UInt64 = 1 << 32

    /// Boot timestamps jitter by a second or so as the clock is disciplined, so
    /// only a change larger than this counts as an actual reboot.
    public static let bootTimeTolerance: TimeInterval = 120

    // MARK: - Per-interface (current)

    /// Folds a per-interface reading into the running totals.
    ///
    /// - Parameters:
    ///   - previous: per-interface counters at the previous sample.
    ///   - previousBootTime: boot time recorded with that sample, if known.
    ///   - current: per-interface counters now.
    ///   - currentBootTime: boot time now, if known.
    /// - Returns: the cellular and WiFi bytes to add to the cumulative totals,
    ///   and whether the device rebooted between the two samples.
    public static func deltas(
        previous: [InterfaceCounters],
        previousBootTime: Date?,
        current: [InterfaceCounters],
        currentBootTime: Date?
    ) -> (cellular: DataSize, wifi: DataSize, didReboot: Bool) {
        let rebooted = didReboot(
            previous: previous,
            previousBootTime: previousBootTime,
            current: current,
            currentBootTime: currentBootTime
        )

        // Interfaces are matched by name; the last entry wins if a platform ever
        // reports a name twice.
        var priorByName: [String: InterfaceCounters] = [:]
        for interface in previous { priorByName[interface.name] = interface }

        var cellular: UInt64 = 0
        var wifi: UInt64 = 0

        for interface in current {
            let added: UInt64
            if rebooted {
                added = interface.totalBytes
            } else if let prior = priorByName[interface.name], isSameInstance(prior, interface) {
                added = delta(from: prior, to: interface)
            } else {
                // Newly appeared (a second SIM coming up) or re-created under the
                // same name with a fresh index: everything it has counted is new.
                added = interface.totalBytes
            }

            switch interface.kind {
            case .cellular: cellular &+= added
            case .wifi: wifi &+= added
            }
        }

        return (DataSize(bytes: cellular), DataSize(bytes: wifi), rebooted)
    }

    // MARK: - Summed totals (fallback)

    /// Diffs two *summed* counter totals. Retained for the first sample after an
    /// upgrade — when the stored snapshot predates per-interface counters — and
    /// for any platform that can't break the read out. Without per-interface
    /// detail a drop can't be attributed, so it is treated as a restart exactly
    /// as before: conservative, and never invents traffic.
    ///
    /// - Parameters:
    ///   - previousRaw: the raw counter at the previous sample.
    ///   - currentRaw: the raw counter now.
    /// - Returns: the bytes to add to the cumulative running total, and whether a
    ///   reboot was detected.
    public static func delta(previousRaw: DataSize, currentRaw: DataSize) -> (delta: DataSize, didReboot: Bool) {
        if currentRaw.bytes >= previousRaw.bytes {
            return (DataSize(bytes: currentRaw.bytes - previousRaw.bytes), false)
        } else {
            return (currentRaw, true)
        }
    }

    // MARK: - Classification

    /// Whether the device rebooted between the two samples.
    ///
    /// The boot clock answers this outright. Without it (a snapshot written by a
    /// build that didn't record one, or a platform that can't report one) the
    /// only honest signal left is that a reboot restarts *every* interface at
    /// once, so a single interface restarting is not a reboot.
    static func didReboot(
        previous: [InterfaceCounters],
        previousBootTime: Date?,
        current: [InterfaceCounters],
        currentBootTime: Date?
    ) -> Bool {
        if let previousBootTime, let currentBootTime {
            return abs(currentBootTime.timeIntervalSince(previousBootTime)) > bootTimeTolerance
        }
        guard !previous.isEmpty, !current.isEmpty else { return false }
        return current.allSatisfy { interface in
            guard let prior = priorInstance(of: interface, in: previous) else { return true }
            return countersRestarted(from: prior, to: interface)
        }
    }

    private static func priorInstance(
        of interface: InterfaceCounters, in previous: [InterfaceCounters]
    ) -> InterfaceCounters? {
        guard let prior = previous.last(where: { $0.name == interface.name }) else { return nil }
        return isSameInstance(prior, interface) ? prior : nil
    }

    /// Whether two readings describe the same live interface instance. An index
    /// of `0` means the platform didn't report one, so the name has to do.
    private static func isSameInstance(_ prior: InterfaceCounters, _ current: InterfaceCounters) -> Bool {
        prior.generation == 0 || current.generation == 0 || prior.generation == current.generation
    }

    /// Whether this interface's counters restarted from zero (rather than one of
    /// them having wrapped).
    ///
    /// Packet counters settle it when present: they climb with every byte and
    /// only wrap after billions of packets (terabytes), so a packet count that
    /// fell — or an interface that was counting packets and now reports none —
    /// means the interface itself restarted. Without them, both byte directions
    /// falling in the same interval is the tell: a wrap moves one direction at a
    /// time, and crediting 4 GiB twice would invent traffic that never happened.
    static func countersRestarted(from prior: InterfaceCounters, to current: InterfaceCounters) -> Bool {
        if prior.hasPacketCounts {
            return !current.hasPacketCounts
                || current.inPackets < prior.inPackets
                || current.outPackets < prior.outPackets
        }
        return current.inBytes < prior.inBytes && current.outBytes < prior.outBytes
    }

    /// Bytes to credit for one interface between two readings of the same
    /// instance, within one boot.
    private static func delta(from prior: InterfaceCounters, to current: InterfaceCounters) -> UInt64 {
        if countersRestarted(from: prior, to: current) { return current.totalBytes }
        return directionDelta(previous: prior.inBytes, current: current.inBytes)
            &+ directionDelta(previous: prior.outBytes, current: current.outBytes)
    }

    /// Bytes to credit for one direction of one interface, adding back a 32-bit
    /// wrap when the counter rolled over.
    private static func directionDelta(previous: UInt64, current: UInt64) -> UInt64 {
        if current >= previous { return current - previous }
        // A counter above the 32-bit range can't have wrapped at 2³², so the only
        // remaining explanation is a restart: count from zero as before.
        guard previous < counterWidth else { return current }
        return (counterWidth - previous) &+ current
    }
}
