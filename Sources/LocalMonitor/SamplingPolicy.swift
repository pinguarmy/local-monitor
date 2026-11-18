import Foundation

/// On-demand sampling rules: no fixed periodic polling for battery or devices.
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

    /// The battery is never polled: only system power events and manual refresh update it.
    /// Asserted nil; callers must not create a timer from it.
    static var batteryPollingInterval: TimeInterval? { nil }

    /// Devices are never polled: read only when the Devices tab opens or on manual refresh.
    /// Asserted nil; callers must not create a timer from it.
    static var devicePollingInterval: TimeInterval? { nil }
}
