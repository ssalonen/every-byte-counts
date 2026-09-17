import Foundation

#if canImport(Darwin)
import Darwin

/// Reads the cellular and WiFi byte counters from the BSD interface list via
/// `getifaddrs`, reporting each interface's `if_data` fields **separately**
/// (design §1, open item §7).
///
/// Interface naming on iOS:
///   * Cellular (PDP) interfaces are named `pdp_ipN` (e.g. `pdp_ip0`). Multiple
///     can be present (IPv4/IPv6, dual-SIM), so all `pdp_ip*` are reported.
///   * WiFi is `en0`. Wired/USB and other `enN` are not WiFi, so only `en0` is
///     counted for the contextual WiFi figure.
///
/// The counters in `if_data` are 32-bit and wrap every 4 GiB, each direction of
/// each interface independently. They are therefore *not* summed here: the
/// sampling engine diffs them one by one and adds the wrap back, which a
/// pre-summed total makes impossible (see `RebootAdjuster`). The read also
/// carries `kern.boottime`, so a reboot is known rather than inferred from a
/// counter that happened to fall.
public struct InterfaceCounterReader: CounterReader {

    /// Prefix that identifies cellular packet-data interfaces.
    public static let cellularPrefix = "pdp_ip"
    /// The WiFi interface name on iOS.
    public static let wifiInterface = "en0"

    public init() {}

    public func read() throws -> CounterReading {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else {
            throw CounterReaderError.interfaceEnumerationFailed
        }
        defer { freeifaddrs(ifaddrPtr) }

        var interfaces: [InterfaceCounters] = []

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let ptr = cursor {
            defer { cursor = ptr.pointee.ifa_next }

            let addr = ptr.pointee.ifa_addr
            // Only AF_LINK entries carry the if_data traffic counters.
            guard addr?.pointee.sa_family == UInt8(AF_LINK) else { continue }

            let name = String(cString: ptr.pointee.ifa_name)
            let kind: InterfaceCounters.Kind
            if name.hasPrefix(Self.cellularPrefix) {
                kind = .cellular
            } else if name == Self.wifiInterface {
                kind = .wifi
            } else {
                continue
            }

            guard let data = ptr.pointee.ifa_data?
                .assumingMemoryBound(to: if_data.self).pointee else { continue }

            interfaces.append(
                InterfaceCounters(
                    name: name,
                    kind: kind,
                    // The index changes when iOS tears an interface down and
                    // re-creates it (airplane mode, SIM switch), which is how a
                    // restarted counter is told from a wrapped one.
                    generation: if_nametoindex(ptr.pointee.ifa_name),
                    inBytes: UInt64(data.ifi_ibytes),
                    outBytes: UInt64(data.ifi_obytes),
                    inPackets: UInt64(data.ifi_ipackets),
                    outPackets: UInt64(data.ifi_opackets)
                )
            )
        }

        return CounterReading(interfaces: interfaces, bootTime: Self.bootTime())
    }

    /// The instant the device last booted, from `kern.boottime`. `nil` if the
    /// sysctl is unavailable, in which case the engine falls back to inferring
    /// reboots from the counters themselves.
    static func bootTime() -> Date? {
        var value = timeval()
        var size = MemoryLayout<timeval>.stride
        guard sysctlbyname("kern.boottime", &value, &size, nil, 0) == 0, value.tv_sec != 0 else {
            return nil
        }
        return Date(timeIntervalSince1970: Double(value.tv_sec) + Double(value.tv_usec) / 1_000_000)
    }
}
#endif
