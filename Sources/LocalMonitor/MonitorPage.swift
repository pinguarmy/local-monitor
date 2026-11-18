import Foundation

/// Panel tabs for the monitor UI. Raw values double as `--preview-page` arguments.
enum MonitorPage: String, CaseIterable {
    case system
    case battery
    case devices

    var label: String { L10n.pageLabel(self) }
}
