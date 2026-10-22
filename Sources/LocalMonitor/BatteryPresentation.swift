import Foundation
import BatteryCore

/// Pure display rules shared by the menu bar and panel, independently testable.
enum BatteryPresentation {
    static func status(_ snapshot: BatterySnapshot) -> String {
        if snapshot.availability == .unknown { return "电池数据读取失败" }
        guard snapshot.isPresent else { return "未检测到内置电池" }
        if snapshot.isCharging == true { return "正在充电" }
        if snapshot.isCharged == true { return "已充满" }
        if snapshot.powerSource == "AC Power" {
            return snapshot.isCharging == false ? "已接电 · 未充电" : "已接电 · 充电状态未知"
        }
        if snapshot.powerSource == "Battery Power" { return "使用电池" }
        return "电源状态未知"
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

}

/// Panel tabs for the monitor UI.
enum MonitorPage: String, CaseIterable {
    case system
    case battery
    case devices

    var label: String {
        switch self {
        case .system: return "系统"
        case .battery: return "电池"
        case .devices: return "设备"
        }
    }
}

/// On-demand sampling rules: no fixed periodic polling for battery or devices.
enum SamplingPolicy {
    /// Real-time system metrics are sampled only while the panel is visible,
    /// the system page is shown, and the machine is not sleeping.
    /// Low power mode widens the interval from 2s to 5s. Otherwise: no timer.
    static func systemInterval(panelVisible: Bool, page: MonitorPage, isSleeping: Bool, lowPower: Bool) -> TimeInterval? {
        guard panelVisible, page == .system, !isSleeping else { return nil }
        return lowPower ? 5 : 2
    }

    /// 电池永不周期轮询：仅系统电源事件与手动刷新驱动更新。
    /// 断言为 nil，调用方不得据此创建任何定时器。
    static var batteryPollingInterval: TimeInterval? { nil }

    /// 设备永不周期轮询：仅进入设备页或手动刷新时按需读取。
    /// 断言为 nil，调用方不得据此创建任何定时器。
    static var devicePollingInterval: TimeInterval? { nil }
}
