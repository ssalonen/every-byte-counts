import Foundation

#if canImport(Darwin)
import Darwin

/// Reads the cellular and WiFi byte counters from the BSD interface list via
/// `getifaddrs`, summing the `if_data` byte fields across the relevant
/// interfaces (design §1, open item §7).
///
/// Interface naming on iOS:
///   * Cellular (PDP) interfaces are named `pdp_ipN` (e.g. `pdp_ip0`). Multiple
///     can be present (IPv4/IPv6, dual-SIM), so all `pdp_ip*` are summed.
///   * WiFi is `en0`. Wired/USB and other `enN` are not WiFi, so only `en0` is
///     counted for the contextual WiFi figure.
///
/// Counters are 32-bit on the BSD `if_data` struct and wrap; the sampling engine
/// already tolerates a *decrease* (it treats it as a reboot/wrap and re-bases),
/// so occasional wraps degrade to a small, accepted inaccuracy rather than a bug.
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

        var cellular: UInt64 = 0
        var wifi: UInt64 = 0

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let ptr = cursor {
            defer { cursor = ptr.pointee.ifa_next }

            let addr = ptr.pointee.ifa_addr
            // Only AF_LINK entries carry the if_data traffic counters.
            guard addr?.pointee.sa_family == UInt8(AF_LINK) else { continue }

            let name = String(cString: ptr.pointee.ifa_name)
            guard let data = ptr.pointee.ifa_data?
                .assumingMemoryBound(to: if_data.self).pointee else { continue }

            let bytes = UInt64(data.ifi_ibytes) + UInt64(data.ifi_obytes)

            if name.hasPrefix(Self.cellularPrefix) {
                cellular += bytes
            } else if name == Self.wifiInterface {
                wifi += bytes
            }
        }

        return CounterReading(
            cellular: DataSize(bytes: cellular),
            wifi: DataSize(bytes: wifi)
        )
    }
}
#endif
