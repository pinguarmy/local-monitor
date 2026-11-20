import Foundation
import BatteryCore
import SystemCore

/// Everything the menu bar item shows, decided without AppKit so tests can assert it.
struct StatusItemContent: Equatable {
    /// SF Symbol candidates in fallback order (resolved by `StatusItemGlyph.firstAvailable`).
    let symbols: [String]
    /// Text after the glyph, with its leading space; empty for a glyph alone.
    let title: String
    let toolTip: String
    let accessibilityValue: String
    /// Battery mode only: compose a separate bolt next to the battery glyph.
    let showsChargingIndicator: Bool
}

/// How the button arranges glyph and title once the glyph has (or has not) resolved.
enum StatusItemImageLayout: Equatable {
    case imageOnly, imageLeading, titleOnly
}

struct StatusItemLayout: Equatable {
    let title: String
    let image: StatusItemImageLayout
}

/// Pure status item rules for every `MenuBarMetric`. Battery rules live in `BatteryPresentation`.
enum StatusItemPresentation {
    static let cpuSymbols = ["cpu", "gauge", "chart.bar"]
    static let memorySymbols = ["memorychip", "square.stack.3d.up", "chart.bar"]
    /// Title before the first valid CPU delta (or when memory could not be read). Keeps the
    /// percent sign so the width stays close to a real value.
    static let placeholderTitle = " –%"

    /// Whole-number percent, clamped to 0...100; nil for a missing or non-finite value.
    static func wholePercent(_ value: Double?) -> String? {
        guard let value, value.isFinite else { return nil }
        let clamped = min(max(value, 0), 100)
        return MonitorFormat.integerPercent(Int(clamped.rounded()))
    }

    static func content(metric: MenuBarMetric, battery: BatterySnapshot, load: SystemLoadSample?) -> StatusItemContent {
        switch metric {
        case .battery:
            // A Mac without a battery gets the neutral gauge from the battery rules.
            return StatusItemContent(
                symbols: BatteryPresentation.statusItemSymbols(battery),
                title: BatteryPresentation.statusItemTitle(battery),
                toolTip: BatteryPresentation.statusItemToolTip(battery),
                accessibilityValue: BatteryPresentation.statusItemAccessibilityValue(battery),
                showsChargingIndicator: battery.availability != .absent && battery.isCharging == true)
        case .cpu:
            let percentage = wholePercent(load?.cpuUsagePercent)
            return StatusItemContent(
                symbols: cpuSymbols,
                title: percentage.map { " " + $0 } ?? placeholderTitle,
                toolTip: L10n.statusItemCPUToolTip(percentage: percentage),
                accessibilityValue: L10n.statusItemCPUAccessibilityValue(percentage: percentage),
                showsChargingIndicator: false)
        case .memory:
            let percentage = wholePercent(load?.memoryUsedPercent)
            return StatusItemContent(
                symbols: memorySymbols,
                title: percentage.map { " " + $0 } ?? placeholderTitle,
                toolTip: L10n.statusItemMemoryToolTip(percentage: percentage),
                accessibilityValue: L10n.statusItemMemoryAccessibilityValue(percentage: percentage),
                showsChargingIndicator: false)
        case .iconOnly:
            return StatusItemContent(
                symbols: BatteryPresentation.noBatterySymbols,
                title: "",
                toolTip: L10n.appName,
                accessibilityValue: L10n.appName,
                showsChargingIndicator: false)
        }
    }

    /// A glyph alone when there is no title; if no glyph resolves, the title alone, and the app
    /// name when that would be empty, so the item never disappears.
    static func layout(title: String, hasGlyph: Bool) -> StatusItemLayout {
        guard hasGlyph else { return StatusItemLayout(title: title.isEmpty ? L10n.appName : title, image: .titleOnly) }
        return StatusItemLayout(title: title, image: title.isEmpty ? .imageOnly : .imageLeading)
    }
}
