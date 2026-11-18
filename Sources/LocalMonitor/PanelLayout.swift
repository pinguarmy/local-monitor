import SwiftUI
import DeviceCore

/// Pure panel layout rules: size constants and scroll identity, shared by the view and tests.
///
/// Root cause this fixes: the ScrollView used to have only frame(maxHeight: 510), with no
/// min/ideal. The Devices tab content is asynchronous (empty, then devices), and AppKit fitting
/// could squeeze the empty scroll viewport to about 100 pt, making the whole panel look flat.
/// A stable minimum/ideal height prevents that; on small screens the parent NSPopover's
/// contentSize adapts further.
enum PanelLayout {
    /// Fixed panel width (points).
    static let panelWidth: CGFloat = 420
    /// Minimum scroll viewport height: the panel never collapses with little or no content.
    static let viewportMinHeight: CGFloat = 480
    /// Ideal scroll viewport height.
    static let viewportIdealHeight: CGFloat = 510
    /// Maximum scroll viewport height: taller content scrolls.
    static let viewportMaxHeight: CGFloat = 510
    /// Fixed height outside the viewport: title row, tabs, divider, footer and panel padding.
    /// viewportIdeal (510) + chrome (140) = 650, matching the NSPopover contentSize 420x650.
    static let chromeHeight: CGFloat = 140
    /// Root view height (620–650). On small screens the NSPopover contentSize adapts further.
    static var panelMinHeight: CGFloat { viewportMinHeight + chromeHeight }
    static var panelIdealHeight: CGFloat { viewportIdealHeight + chromeHeight }
    static var panelMaxHeight: CGFloat { viewportIdealHeight + chromeHeight }
    /// Height budget for showing a device's name and charge on the first screen (header + card header).
    static let deviceFirstScreenBudget: CGFloat = 180

    /// Whether a viewport of this height shows the device name and charge on the first screen.
    static func viewportFitsDeviceFirstScreen(_ viewportHeight: CGFloat) -> Bool {
        viewportHeight >= deviceFirstScreenBudget
    }

    /// Scroll identity: changes only with the tab or the device snapshot's status/count, which
    /// scrolls back to the top. System samples every 2 s and battery events do not take part,
    /// so they never interrupt the scroll position.
    struct ScrollIdentity: Hashable {
        var page: MonitorPage
        var deviceStatus: String
        var deviceCount: Int
    }

    /// Device status/count count only on the Devices tab; other tabs ignore device data.
    static func scrollIdentity(page: MonitorPage, devices: DeviceSnapshot?) -> ScrollIdentity {
        ScrollIdentity(
            page: page,
            deviceStatus: page == .devices ? (devices?.status.rawValue ?? "none") : "ignored",
            deviceCount: page == .devices ? (devices?.devices.count ?? 0) : 0
        )
    }
}
