import Foundation
import Combine

/// What the menu bar item shows next to its glyph. Raw values are stored in UserDefaults and
/// double as `--menu-bar-metric` arguments, so they must not be renamed.
enum MenuBarMetric: String, CaseIterable {
    case battery
    case cpu
    case memory
    case iconOnly

    var label: String { L10n.menuBarMetric(self) }

    /// CPU and memory need background sampling; battery uses power events, icon only nothing.
    var needsLoadSampling: Bool {
        switch self {
        case .cpu, .memory: return true
        case .battery, .iconOnly: return false
        }
    }

    /// Without a stored choice: battery on a Mac that has one, otherwise CPU. A battery read
    /// failure (`.unknown`) still counts as having a battery.
    static func defaultMetric(hasBattery: Bool) -> MenuBarMetric {
        hasBattery ? .battery : .cpu
    }

    /// A stored raw value wins when it is valid; anything else falls back to the default.
    static func resolve(stored: String?, hasBattery: Bool) -> MenuBarMetric {
        stored.flatMap { MenuBarMetric(rawValue: $0) } ?? defaultMetric(hasBattery: hasBattery)
    }
}

/// The user's menu bar choice. Only an explicit selection is written to UserDefaults
/// (key `MenuBarMetric`); a harness override is applied for this run and never persisted.
@MainActor
final class MenuBarSettings: ObservableObject {
    static let defaultsKey = "MenuBarMetric"

    @Published private(set) var metric: MenuBarMetric
    private let defaults: UserDefaults
    private let persists: Bool

    init(defaults: UserDefaults = .standard, hasBattery: Bool, override: MenuBarMetric? = nil) {
        self.defaults = defaults
        persists = override == nil
        metric = override ?? MenuBarMetric.resolve(stored: defaults.string(forKey: Self.defaultsKey), hasBattery: hasBattery)
    }

    func select(_ metric: MenuBarMetric) {
        guard metric != self.metric else { return }
        self.metric = metric
        if persists { defaults.set(metric.rawValue, forKey: Self.defaultsKey) }
    }
}
