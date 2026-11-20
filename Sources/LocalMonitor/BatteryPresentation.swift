import Foundation
import BatteryCore

/// Pure display rules shared by the menu bar item and the Battery tab, independently testable.
enum BatteryPresentation {
    static func status(_ snapshot: BatterySnapshot) -> String {
        switch snapshot.availability {
        case .unknown: return L10n.batteryReadFailed
        case .absent: return L10n.batteryAbsent
        case .present: break
        }
        if snapshot.isCharging == true { return L10n.batteryCharging }
        if snapshot.isCharged == true { return L10n.batteryCharged }
        if snapshot.powerSource == "AC Power" {
            return snapshot.isCharging == false ? L10n.batteryPluggedInNotCharging : L10n.batteryPluggedInUnknown
        }
        if snapshot.powerSource == "Battery Power" { return L10n.batteryOnBattery }
        return L10n.batteryPowerUnknown
    }

    /// Percentage text for the menu bar title and the Battery tab header, nil when not read.
    static func percentage(_ snapshot: BatterySnapshot) -> String? {
        guard snapshot.isPresent, let percentage = snapshot.percentage else { return nil }
        return MonitorFormat.integerPercent(percentage)
    }

    static func symbol(_ snapshot: BatterySnapshot) -> String {
        guard snapshot.isPresent, let percentage = snapshot.percentage else { return "battery.0" }
        let level: Int
        switch percentage {
        case ..<13: level = 0
        case ..<38: level = 25
        case ..<63: level = 50
        case ..<88: level = 75
        default: level = 100
        }
        return "battery.\(level)"
    }

    /// Neutral glyphs for Macs without a battery, in fallback order. `NSImage(systemSymbolName:)`
    /// returns nil for names the running macOS does not know, so callers try each in turn.
    static let noBatterySymbols = ["gauge.medium", "gauge", "chart.bar", "display"]

    /// Status item glyph candidates in fallback order. A read failure (`.unknown`) keeps a
    /// battery glyph so it stays distinguishable from a Mac that has no battery.
    static func statusItemSymbols(_ snapshot: BatterySnapshot) -> [String] {
        switch snapshot.availability {
        case .absent: return noBatterySymbols
        case .present, .unknown: return [symbol(snapshot), "battery.0"]
        }
    }

    /// Menu bar title next to the glyph: nothing for a Mac without a battery.
    static func statusItemTitle(_ snapshot: BatterySnapshot) -> String {
        switch snapshot.availability {
        case .absent: return ""
        case .present, .unknown: return " " + (percentage(snapshot) ?? "—")
        }
    }

    static func statusItemToolTip(_ snapshot: BatterySnapshot) -> String {
        switch snapshot.availability {
        case .absent: return L10n.appName
        case .present, .unknown:
            return L10n.statusItemToolTip(status: status(snapshot), percentage: percentage(snapshot))
        }
    }

    static func statusItemAccessibilityValue(_ snapshot: BatterySnapshot) -> String {
        switch snapshot.availability {
        case .absent: return L10n.appName
        case .present, .unknown:
            return L10n.statusItemAccessibilityValue(status: status(snapshot), percentage: percentage(snapshot))
        }
    }
}
