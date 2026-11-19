import Foundation
import DeviceCore

/// Every periodic read in the app, as pure rules. Panel timers run only while the panel is
/// visible on their tab and the Mac is awake; the menu bar timer runs only for a metric that
/// needs it. Nil means no timer.
enum SamplingPolicy {
    /// Real-time system metrics are sampled only while the panel is visible,
    /// the system page is shown, and the machine is not sleeping.
    /// Low Power Mode widens the interval from 2 s to 5 s. Otherwise: no timer.
    static func systemInterval(panelVisible: Bool, page: MonitorPage, isSleeping: Bool, lowPower: Bool) -> TimeInterval? {
        guard panelVisible, page == .system, !isSleeping else { return nil }
        return lowPower ? 5 : 2
    }

    /// CPU usage and network rates need two samples. When sampling (re)starts, one extra
    /// sample is taken this long after the first so those rows appear quickly; the regular
    /// interval continues unchanged. Nil when there is no timer or the interval is already short.
    static func warmUpDelay(interval: TimeInterval?) -> TimeInterval? {
        guard let interval else { return nil }
        let delay: TimeInterval = 1
        return delay < interval ? delay : nil
    }

    /// The Mac battery is re-read while the panel is visible on the Battery tab and the Mac is
    /// awake, so power, current, temperature and time remaining do not go stale: every 5 s,
    /// 10 s in Low Power Mode. A Mac without a battery has nothing to refresh. Power events,
    /// wake, panel open and manual refresh still update it in addition to this timer.
    static func batteryInterval(panelVisible: Bool, page: MonitorPage, isSleeping: Bool, lowPower: Bool,
                                hasBattery: Bool) -> TimeInterval? {
        guard panelVisible, page == .battery, !isSleeping, hasBattery else { return nil }
        return lowPower ? 10 : 5
    }

    /// Connected devices are re-read silently every 10 s while the panel is visible on the
    /// Devices tab and the Mac is awake, so plugging or unplugging shows up without Refresh.
    /// Never in Low Power Mode, and never after a failed notification cleanup, which needs an
    /// app restart. Opening the tab and manual refresh still read in addition to this timer.
    static func deviceInterval(panelVisible: Bool, page: MonitorPage, isSleeping: Bool, lowPower: Bool,
                               lastIssue: DeviceReadIssue?) -> TimeInterval? {
        guard panelVisible, page == .devices, !isSleeping, !lowPower,
              lastIssue != .notificationCleanupFailed else { return nil }
        return 10
    }

    /// Background sampling for the menu bar title: only for the CPU and memory metrics, every
    /// 3 s (6 s in Low Power Mode), paused while the Mac sleeps. Battery and icon-only modes run
    /// no background sampling at all.
    static func menuBarInterval(metric: MenuBarMetric, isSleeping: Bool, lowPower: Bool) -> TimeInterval? {
        guard metric.needsLoadSampling, !isSleeping else { return nil }
        return lowPower ? 6 : 3
    }

    /// Timer tolerance: lets macOS coalesce wake-ups; the rules above are not exact deadlines.
    static func tolerance(interval: TimeInterval) -> TimeInterval {
        interval * 0.2
    }
}
