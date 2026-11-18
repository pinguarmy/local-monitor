import Foundation
import Combine
import ServiceManagement

/// Bundle facts shown in the panel's "more" menu.
enum AppInfo {
    /// CFBundleShortVersionString; nil for a bare binary without an Info.plist.
    static var version: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }
}

/// Thin wrapper over `SMAppService.mainApp` (macOS 13+) so views only bind a Bool.
/// Unsupported without a bundle identifier (bare test binary, `swift run`): the toggle is hidden
/// and ServiceManagement is never called. Errors are swallowed; `isEnabled` always reflects the
/// real registration status afterwards.
@MainActor
final class LaunchAtLogin: ObservableObject {
    let isSupported: Bool
    @Published private(set) var isEnabled = false

    init(bundleIdentifier: String? = Bundle.main.bundleIdentifier) {
        isSupported = bundleIdentifier != nil
        reload()
    }

    /// Re-reads the status, e.g. after the user changed it in System Settings.
    func reload() {
        guard isSupported else {
            isEnabled = false
            return
        }
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    /// Toggle binding target: reads the real status, writes through `setEnabled(_:)`.
    var wantsEnabled: Bool {
        get { isEnabled }
        set { setEnabled(newValue) }
    }

    func setEnabled(_ enabled: Bool) {
        guard isSupported else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // No alert: the toggle simply keeps showing the real status below.
        }
        reload()
    }
}
