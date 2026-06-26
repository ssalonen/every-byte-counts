import Foundation

/// Identifiers shared across the app and widget targets.
public enum AppConstants {
    /// App Group container shared by the app and widget (design §4). Must match
    /// the App Group capability configured on both targets in Xcode.
    public static let appGroupIdentifier = "group.fi.mailhub.everybytecounts"

    /// WidgetKit kind identifier for the usage widget.
    public static let widgetKind = "EveryByteCountsWidget"
}

/// Display formatting shared by the app and widget so figures read identically
/// everywhere.
public enum Formatters {
    /// Formats a data size with adaptive GB/MB units.
    public static func data(_ size: DataSize) -> String {
        if size.gigabytes >= 1 {
            return String(format: "%.2f GB", size.gigabytes)
        }
        return String(format: "%.0f MB", size.megabytes)
    }

    public static func gigabytes(_ gb: Double) -> String {
        String(format: "%.2f GB", gb)
    }

    public static func euros(_ amount: Double) -> String {
        String(format: "€%.2f", amount)
    }

    public static func percent(_ fraction: Double) -> String {
        String(format: "%.0f%%", fraction * 100)
    }
}
