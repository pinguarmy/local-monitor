import Foundation

/// Number and unit formatting. Units (GB, °C, mAh, W ...) read the same in both UI languages;
/// anything with words goes through `L10n`.
enum MonitorFormat {
    static func bytes(_ value: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: Int64(clamping: value))
    }

    static func bytesPerSecond(_ value: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        formatter.allowsNonnumericFormatting = false
        let safe = value.isFinite ? min(Double(Int64.max / 2), max(0, value)) : 0
        return L10n.perSecond(formatter.string(fromByteCount: Int64(safe)))
    }

    static func percent(_ value: Double) -> String {
        String(format: "%.1f%%", value)
    }

    static func roundedPercent(_ value: Double) -> String {
        String(format: "%.0f%%", value)
    }

    static func integerPercent(_ value: Int) -> String {
        "\(value)%"
    }

    static func loadAverage(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    static func celsius(_ value: Double) -> String {
        String(format: "%.1f °C", value)
    }

    static func volts(_ value: Double) -> String {
        String(format: "%.3f V", value)
    }

    static func milliamps(_ value: Double) -> String {
        String(format: "%.0f mA", value)
    }

    static func signedWatts(_ value: Double) -> String {
        String(format: "%+.2f W", value)
    }

    static func watts(_ value: Int) -> String {
        "\(value) W"
    }

    static func milliampHours(_ value: Int) -> String {
        "\(value) mAh"
    }

    static func uptime(_ seconds: Double) -> String? {
        guard seconds.isFinite, seconds >= 0, let total = Int(exactly: seconds.rounded(.towardZero)) else { return nil }
        return L10n.uptimeValue(days: total / 86400, hours: (total % 86400) / 3600, minutes: (total % 3600) / 60)
    }

    /// Hours and minutes; nil for non-positive values (unavailable, never a placeholder).
    static func duration(minutes: Int) -> String? {
        guard minutes > 0 else { return nil }
        return L10n.duration(minutes: minutes)
    }
}
