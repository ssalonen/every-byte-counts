import Foundation

/// One interface's raw counters as the kernel reports them, kept **per interface
/// and per direction** rather than pre-summed (design §1).
///
/// The BSD `if_data` fields behind `getifaddrs` are 32-bit: `ifi_ibytes` and
/// `ifi_obytes` each wrap back to zero every 4 GiB, independently of one another
/// and of the other interfaces. Summing them before diffing throws away exactly
/// the information needed to tell a wrap ("add the 4 GiB back") from a counter
/// restart ("count up from zero again"), which is how gigabytes of real traffic
/// could go missing from a cycle total — see
/// `docs/TEST-ASSESSMENT.md`, finding 🔴.
public struct InterfaceCounters: Equatable, Codable, Sendable {

    /// Which meter an interface's traffic belongs to.
    public enum Kind: String, Codable, Sendable {
        case cellular
        case wifi
    }

    /// Interface name as the kernel reports it (`pdp_ip0`, `en0`, …).
    public var name: String
    public var kind: Kind

    /// Identifies the interface *instance* — the kernel's interface index.
    ///
    /// iOS tears down and re-creates `pdp_ip0` on an airplane-mode or
    /// cellular-data toggle and on a SIM switch, which zeroes its counters with
    /// no reboot involved. The re-created interface is handed a fresh index, so
    /// a change here means "these counters restarted", never "they wrapped".
    /// `0` means the platform could not report one.
    public var generation: UInt32

    /// Raw received byte counter as read (wraps at 2³²).
    public var inBytes: UInt64
    /// Raw sent byte counter as read (wraps at 2³²).
    public var outBytes: UInt64

    /// Raw packet counters, carried only as corroboration: they advance with
    /// every read and only wrap after ~4.3 billion packets (terabytes of
    /// traffic), so a packet counter that *went backwards* is near-proof the
    /// interface restarted rather than that its byte counter wrapped. `0` on
    /// both means "not reported".
    public var inPackets: UInt64
    public var outPackets: UInt64

    public init(
        name: String,
        kind: Kind,
        generation: UInt32 = 0,
        inBytes: UInt64,
        outBytes: UInt64,
        inPackets: UInt64 = 0,
        outPackets: UInt64 = 0
    ) {
        self.name = name
        self.kind = kind
        self.generation = generation
        self.inBytes = inBytes
        self.outBytes = outBytes
        self.inPackets = inPackets
        self.outPackets = outPackets
    }

    /// Bytes counted in both directions since this interface instance appeared.
    public var totalBytes: UInt64 { inBytes &+ outBytes }

    /// Whether packet counters are available to corroborate a byte-counter drop.
    public var hasPacketCounts: Bool { inPackets > 0 || outPackets > 0 }
}
