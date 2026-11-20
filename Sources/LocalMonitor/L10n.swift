import Foundation
import SystemCore
import DeviceCore

/// The two UI languages. English is the default; anything starting with "zh" selects Simplified Chinese.
enum AppLanguage: String, CaseIterable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    /// Maps a localization or language code ("en", "en-GB", "zh-Hans", "zh_CN", ...) to a UI language.
    static func matching(_ code: String) -> AppLanguage {
        code.lowercased().hasPrefix("zh") ? .simplifiedChinese : .english
    }

    /// Pure resolution rule: an explicit `--language <code>` argument wins,
    /// otherwise the first preferred localization decides.
    static func resolve(arguments: [String], preferredLocalizations: [String]) -> AppLanguage {
        if let index = arguments.firstIndex(of: "--language"), arguments.indices.contains(index + 1) {
            return matching(arguments[index + 1])
        }
        guard let first = preferredLocalizations.first else { return .english }
        return matching(first)
    }

    /// Resolved once at first use of `L10n.language`.
    /// A bundle without declared localizations (bare test binary, `swift run`) has no meaningful
    /// `preferredLocalizations`, so the user's language preferences are matched against the
    /// supported list directly in that case.
    static func launchDefault() -> AppLanguage {
        let bundle = Bundle.main
        let declared = bundle.localizations.contains { $0.lowercased().hasPrefix("zh") }
        let preferred = declared
            ? bundle.preferredLocalizations
            : Bundle.preferredLocalizations(from: AppLanguage.allCases.map { $0.rawValue })
        return resolve(arguments: CommandLine.arguments, preferredLocalizations: preferred)
    }
}

/// Typed UI string catalog. Every entry goes through `tr(en:zh:)`, so a missing translation
/// is a compile error. Views, AppDelegate and the display rules never inline user-facing text.
enum L10n {
    /// Overridable by tests and by the `--language` launch argument (read in `launchDefault()`).
    static var language: AppLanguage = AppLanguage.launchDefault()

    private static func tr(en: String, zh: String) -> String {
        switch language {
        case .english: return en
        case .simplifiedChinese: return zh
        }
    }

    // MARK: App and panel chrome

    static var appName: String { tr(en: "Local Monitor", zh: "本机监控") }
    static var panelBadge: String { tr(en: "Local · Read-only", zh: "本地 · 只读") }
    static var pagePickerLabel: String { tr(en: "Monitor page", zh: "监控页面") }
    static var refresh: String { tr(en: "Refresh", zh: "刷新") }
    static var quit: String { tr(en: "Quit", zh: "退出") }
    static var moreMenu: String { tr(en: "More", zh: "更多") }
    static var launchAtLogin: String { tr(en: "Launch at Login", zh: "登录时启动") }
    static func version(_ version: String) -> String {
        tr(en: "Version \(version)", zh: "版本 \(version)")
    }

    static func pageLabel(_ page: MonitorPage) -> String {
        switch page {
        case .system: return tr(en: "System", zh: "系统")
        case .battery: return tr(en: "Battery", zh: "电池")
        case .devices: return tr(en: "Devices", zh: "设备")
        }
    }

    /// Footer caption while the System tab samples on a timer.
    static func systemSamplingEvery(seconds: Int) -> String {
        tr(en: "Every \(seconds) s while open · stops on close", zh: "查看时每\(seconds)秒 · 关闭即停")
    }
    static var systemSamplingPaused: String { tr(en: "Live sampling paused", zh: "实时采样已暂停") }
    /// Footer caption while the Battery tab refreshes on a timer.
    static func batteryRefreshEvery(seconds: Int) -> String {
        tr(en: "Updates every \(seconds) s while shown", zh: "查看时每\(seconds)秒更新")
    }
    /// Footer caption on the Battery tab when there is nothing to refresh on a timer.
    static var batteryEventsOnlyCaption: String { tr(en: "Updates on power events", zh: "电源事件时更新") }
    /// Footer caption while the Devices tab re-reads on a timer.
    static func devicesCheckEvery(seconds: Int) -> String {
        tr(en: "Checks every \(seconds) s while shown", zh: "查看时每\(seconds)秒检查")
    }
    /// Footer caption on the Devices tab without a timer (Low Power Mode, or a reader that needs a restart).
    static var devicesPolicyCaption: String { tr(en: "Read on open and Refresh only", zh: "设备仅打开时与手动读取") }

    static func updated(at date: Date) -> String {
        let time = DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
        return tr(en: "Updated \(time)", zh: "更新于 \(time)")
    }

    // MARK: Status item

    static var chargingIndicator: String { tr(en: "Charging", zh: "正在充电") }
    static func statusItemToolTip(status: String, percentage: String?) -> String {
        guard let percentage else { return tr(en: "\(appName) · \(status)", zh: "\(appName) · \(status)") }
        return tr(en: "\(appName) · \(status) · \(percentage)", zh: "\(appName) · \(status) · \(percentage)")
    }
    static func statusItemAccessibilityValue(status: String, percentage: String?) -> String {
        guard let percentage else { return status }
        return tr(en: "\(percentage), \(status)", zh: "\(percentage)，\(status)")
    }
    static func statusItemCPUToolTip(percentage: String?) -> String {
        guard let percentage else { return tr(en: "\(appName) · CPU usage · measuring…", zh: "\(appName) · CPU 使用率 · 测量中…") }
        return tr(en: "\(appName) · CPU usage \(percentage)", zh: "\(appName) · CPU 使用率 \(percentage)")
    }
    static func statusItemCPUAccessibilityValue(percentage: String?) -> String {
        guard let percentage else { return tr(en: "CPU usage, measuring", zh: "CPU 使用率，测量中") }
        return tr(en: "CPU usage \(percentage)", zh: "CPU 使用率 \(percentage)")
    }
    static func statusItemMemoryToolTip(percentage: String?) -> String {
        guard let percentage else { return tr(en: "\(appName) · Memory used · measuring…", zh: "\(appName) · 内存已用 · 测量中…") }
        return tr(en: "\(appName) · Memory used \(percentage)", zh: "\(appName) · 内存已用 \(percentage)")
    }
    static func statusItemMemoryAccessibilityValue(percentage: String?) -> String {
        guard let percentage else { return tr(en: "Memory used, measuring", zh: "内存已用，测量中") }
        return tr(en: "Memory used \(percentage)", zh: "内存已用 \(percentage)")
    }

    // MARK: Menu bar choice ("more" menu)

    static var menuBarShows: String { tr(en: "Menu Bar Shows", zh: "菜单栏显示") }
    static func menuBarMetric(_ metric: MenuBarMetric) -> String {
        switch metric {
        case .battery: return tr(en: "Battery", zh: "电池")
        case .cpu: return tr(en: "CPU Usage", zh: "CPU 使用率")
        case .memory: return tr(en: "Memory Usage", zh: "内存使用")
        case .iconOnly: return tr(en: "Icon Only", zh: "仅图标")
        }
    }

    // MARK: System tab

    static var sampling: String { tr(en: "Sampling…", zh: "采样中…") }
    static var systemNotSampled: String {
        tr(en: "Not sampled yet. Sampling starts when the panel opens.", zh: "尚未采样。打开面板后开始采集。")
    }
    static var groupCPU: String { tr(en: "CPU", zh: "CPU") }
    static var groupGPU: String { tr(en: "GPU", zh: "GPU") }
    static var groupMemory: String { tr(en: "Memory", zh: "内存") }
    static var groupDisk: String { tr(en: "Disk", zh: "磁盘") }
    static var groupNetwork: String { tr(en: "Network", zh: "网络") }
    static var groupMachine: String { tr(en: "Machine", zh: "整机状态") }

    static var cpuUsage: String { tr(en: "Usage", zh: "使用率") }
    static var cpuUsageAccessibility: String { tr(en: "CPU usage", zh: "CPU 使用率") }
    static var cpuCores: String { tr(en: "Cores", zh: "核心") }
    static func coreCounts(logical: Int, physical: Int?) -> String {
        guard let physical else { return tr(en: "\(logical) logical", zh: "\(logical) 逻辑核") }
        return tr(en: "\(logical) logical · \(physical) physical", zh: "\(logical) 逻辑核 · \(physical) 物理核")
    }
    static var cpuLoad: String { tr(en: "Load", zh: "负载") }
    /// Entries are (window in minutes, formatted load value), only those actually sampled.
    static func loadAverages(_ entries: [(minutes: Int, value: String)]) -> String {
        entries.map { entry in
            tr(en: "\(entry.minutes)m \(entry.value)", zh: "\(entry.minutes)分 \(entry.value)")
        }.joined(separator: " · ")
    }
    static var gpuModel: String { tr(en: "Model", zh: "型号") }
    static var gpuUtilization: String { tr(en: "Utilization", zh: "利用率") }

    static var usedOfTotal: String { tr(en: "Used / Total", zh: "已用 / 总量") }
    static func pair(_ first: String, _ second: String) -> String {
        tr(en: "\(first) / \(second)", zh: "\(first) / \(second)")
    }
    static var available: String { tr(en: "Available", zh: "可用") }
    static var compressed: String { tr(en: "Compressed", zh: "已压缩") }
    static var swap: String { tr(en: "Swap", zh: "交换") }
    static var memoryUsageAccessibility: String { tr(en: "Memory usage", zh: "内存使用") }
    static var memoryPressure: String { tr(en: "Memory pressure", zh: "内存压力") }
    static func memoryPressureLevel(_ pressure: MemoryPressure) -> String {
        switch pressure {
        case .normal: return tr(en: "Normal", zh: "正常")
        case .warning: return tr(en: "Elevated", zh: "紧张")
        case .critical: return tr(en: "Critical", zh: "危急")
        case .unknown: return tr(en: "Unknown", zh: "未知")
        }
    }
    static var diskUsageAccessibility: String { tr(en: "Disk usage", zh: "磁盘使用") }

    static var download: String { tr(en: "Download", zh: "下载") }
    static var upload: String { tr(en: "Upload", zh: "上传") }
    static var receivedSent: String { tr(en: "Total in / out", zh: "累计收 / 发") }
    static func perSecond(_ amount: String) -> String {
        tr(en: "\(amount)/s", zh: "\(amount)/s")
    }

    static var uptime: String { tr(en: "Uptime", zh: "运行时间") }
    static func uptimeValue(days: Int, hours: Int, minutes: Int) -> String {
        if days > 0 { return tr(en: "\(days) d \(hours) h", zh: "\(days) 天 \(hours) 小时") }
        if hours > 0 { return tr(en: "\(hours) h \(minutes) min", zh: "\(hours) 小时 \(minutes) 分") }
        return tr(en: "\(minutes) min", zh: "\(minutes) 分")
    }
    static var thermalState: String { tr(en: "Thermal state", zh: "热状态") }
    static func thermalLevel(_ state: ThermalState) -> String {
        switch state {
        case .nominal: return tr(en: "Normal", zh: "正常")
        case .fair: return tr(en: "Fair", zh: "偏高")
        case .serious: return tr(en: "Serious", zh: "严重")
        case .critical: return tr(en: "Critical", zh: "危急")
        case .unknown: return tr(en: "Unknown", zh: "未知")
        }
    }
    static var lowPowerMode: String { tr(en: "Low Power Mode", zh: "低功耗模式") }
    static func onOff(_ on: Bool) -> String {
        on ? tr(en: "On", zh: "已开启") : tr(en: "Off", zh: "已关闭")
    }

    // MARK: Battery tab

    static var batteryReadFailed: String { tr(en: "Couldn't read battery data", zh: "电池数据读取失败") }
    static var batteryAbsent: String { tr(en: "No internal battery", zh: "未检测到内置电池") }
    static var batteryCharging: String { tr(en: "Charging", zh: "正在充电") }
    static var batteryCharged: String { tr(en: "Fully charged", zh: "已充满") }
    static var batteryPluggedInNotCharging: String { tr(en: "Plugged in · not charging", zh: "已接电 · 未充电") }
    static var batteryPluggedInUnknown: String { tr(en: "Plugged in · charging status unknown", zh: "已接电 · 充电状态未知") }
    static var batteryOnBattery: String { tr(en: "On battery", zh: "使用电池") }
    static var batteryPowerUnknown: String { tr(en: "Power source unknown", zh: "电源状态未知") }

    static var batteryAbsentTitle: String { tr(en: "No Internal Battery", zh: "未检测到内置电池") }
    static var batteryAbsentMessage: String { tr(en: "This Mac has no internal battery.", zh: "这台 Mac 没有内置电池。") }
    static var batteryUnknownTitle: String { tr(en: "Couldn't Read Battery Data", zh: "电池数据读取失败") }
    static var batteryUnknownMessage: String { tr(en: "Click Refresh to try again.", zh: "请点击“刷新”重试。") }
    static var batteryPartialReadWarning: String {
        tr(en: "Some battery data couldn't be read. Try Refresh. Missing values are never shown as zero.",
           zh: "部分系统数据读取失败，请尝试刷新。缺失值不会当作零。")
    }
    static var batteryLevelAccessibility: String { tr(en: "Battery level", zh: "电量") }

    static var timeRemaining: String { tr(en: "Time remaining", zh: "剩余使用时间") }
    static var timeToFull: String { tr(en: "Time to full", zh: "充满还需") }
    static var powerAdapter: String { tr(en: "Power adapter", zh: "电源适配器") }
    static func duration(minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        if hours > 0 && rest > 0 { return tr(en: "\(hours) h \(rest) min", zh: "\(hours) 小时 \(rest) 分") }
        if hours > 0 { return tr(en: "\(hours) h", zh: "\(hours) 小时") }
        return tr(en: "\(rest) min", zh: "\(rest) 分")
    }

    static var batteryCondition: String { tr(en: "Condition", zh: "系统健康状态") }
    /// Known IOPowerSources condition strings are translated; English shows them as macOS
    /// reports them. Anything else passes through unchanged.
    static func batteryConditionValue(_ raw: String) -> String {
        switch raw {
        case "Good": return tr(en: "Good", zh: "良好")
        case "Fair": return tr(en: "Fair", zh: "一般")
        case "Poor": return tr(en: "Poor", zh: "较差")
        case "Check Battery": return tr(en: "Check Battery", zh: "检查电池")
        case "Permanent Failure": return tr(en: "Permanent Failure", zh: "永久故障")
        default: return raw
        }
    }
    static var batteryReportedMaximum: String { tr(en: "Maximum capacity", zh: "系统最大容量") }
    static var batteryCapacityRatio: String { tr(en: "Capacity ratio · estimate", zh: "容量比 · 估算健康") }
    static var batteryFullChargeCapacity: String { tr(en: "Full-charge capacity", zh: "当前最大容量") }
    static var designCapacity: String { tr(en: "Design capacity", zh: "设计容量") }
    static var cycleCount: String { tr(en: "Cycle count", zh: "循环次数") }
    static var batteryTemperature: String { tr(en: "Battery temperature", zh: "电池温度") }
    static var voltage: String { tr(en: "Voltage", zh: "电压") }
    static var current: String { tr(en: "Current", zh: "电流") }
    static var batteryPower: String { tr(en: "Power · battery side", zh: "功率 · 电池侧估算") }
    static var batteryPowerFootnote: String {
        tr(en: "Positive power flows into the battery; negative is discharge. Not whole-system or adapter power.",
           zh: "功率正值为流入电池，负值为放电；不是整机功耗或充电器功率。")
    }
    static var capacityRatioFootnote: String {
        tr(en: "The capacity ratio can exceed 100%.", zh: "容量比可能高于 100%。")
    }

    // MARK: Devices tab

    static var reading: String { tr(en: "Reading…", zh: "读取中…") }
    static var devicesNotRead: String {
        tr(en: "Not read yet. Devices are read only while this tab is shown or when you click Refresh.",
           zh: "尚未读取。仅在查看设备页时或点击刷新时读取。")
    }
    static var deviceNote: String {
        tr(en: "Device information is read-only. Nothing is paired automatically and no personal content is read. Device numbers only label this list.",
           zh: "本页只读设备信息，不自动配对或读取个人内容。设备编号仅用于当前列表。")
    }
    static var status: String { tr(en: "Status", zh: "状态") }
    static var noDeviceConnected: String { tr(en: "No device connected", zh: "未连接设备") }
    static var unlockAndTrustRequired: String { tr(en: "Unlock and trust required", zh: "需要解锁并信任") }
    static var interfaceUnavailable: String { tr(en: "System interface unavailable", zh: "系统接口不可用") }
    static var readTimedOut: String { tr(en: "Timed out", zh: "读取超时") }

    static var availableButEmptyDetail: String {
        tr(en: "The interface is available, but no device was detected.", zh: "接口可用，但当前没有检测到设备。")
    }
    static var noDeviceDetail: String {
        tr(en: "No iPhone or iPad is connected.", zh: "没有检测到已连接的 iPhone 或 iPad。")
    }
    static var unavailableDetail: String {
        tr(en: "This Mac doesn't provide the interface for reading connected devices.",
           zh: "当前系统没有提供读取外接设备的接口，无法列出设备。")
    }
    static var timedOutDetail: String {
        tr(en: "The device didn't respond in time. Unlock it, keep it connected, then click Refresh.",
           zh: "设备没有在限定时间内响应。请确认设备已解锁并保持连接，然后点击“刷新”重试。")
    }
    static func deviceIssue(_ issue: DeviceReadIssue) -> String {
        switch issue {
        case .frameworkUnavailable:
            return tr(en: "The system framework for connected devices isn't available on this Mac.",
                      zh: "这台 Mac 上没有可用的设备系统框架，无法读取外接设备。")
        case .subscriptionFailed:
            return tr(en: "Couldn't start watching for connected devices. Click Refresh to try again.",
                      zh: "无法开始监听设备连接，请点击“刷新”重试。")
        case .notificationCleanupFailed:
            return tr(en: "A previous device watcher didn't shut down cleanly. Restart Local Monitor to read devices again.",
                      zh: "上次的设备监听没有正常结束。请重新启动本机监控后再读取。")
        case .readInProgress:
            return tr(en: "The previous read is still finishing. Try again in a few seconds.",
                      zh: "上一次读取仍在进行，请稍等几秒再试。")
        case .deviceUnreadable:
            return tr(en: "A connected device couldn't be read. Unlock it, check the cable, then click Refresh.",
                      zh: "已连接的设备无法读取。请解锁设备并检查数据线，然后点击“刷新”。")
        }
    }

    static var stepConnectCable: String {
        tr(en: "Connect the iPhone or iPad with a USB data cable (wireless isn't supported).",
           zh: "用 USB 数据线连接 iPhone / iPad（无线连接不在支持范围内）。")
    }
    static var stepUnlockAndTrustYourself: String {
        tr(en: "Unlock the device and confirm “Trust This Computer” on it yourself.",
           zh: "解锁设备，并在设备上自行确认“信任此电脑”。")
    }
    static var stepKeepConnectedAndUnlock: String {
        tr(en: "Keep the USB cable connected and unlock the iPhone or iPad.",
           zh: "保持 USB 连接，解锁 iPhone / iPad。")
    }
    static var stepConfirmTrust: String {
        tr(en: "Confirm “Trust This Computer” on the device. You confirm it yourself; this app never pairs for you.",
           zh: "在设备上确认“信任此电脑”（由你手动确认，本应用不会替你配对）。")
    }
    static var stepClickRefresh: String {
        tr(en: "Click Refresh at the bottom of the panel.", zh: "点击面板底部的“刷新”重新读取。")
    }

    static func deviceKind(_ kind: DeviceKind) -> String {
        switch kind {
        case .iPhone: return tr(en: "iPhone", zh: "iPhone")
        case .iPad: return tr(en: "iPad", zh: "iPad")
        }
    }
    static var deviceBatteryAccessibility: String { tr(en: "Device battery", zh: "设备电量") }
    static var osVersion: String { tr(en: "OS version", zh: "系统版本") }
    static func osVersionValue(kind: DeviceKind, version: String) -> String {
        switch kind {
        case .iPhone: return tr(en: "iOS \(version)", zh: "iOS \(version)")
        case .iPad: return tr(en: "iPadOS \(version)", zh: "iPadOS \(version)")
        }
    }
    static var chargingStatus: String { tr(en: "Charging status", zh: "充电状态") }
    static func chargingState(_ state: DeviceChargingState) -> String {
        switch state {
        case .charging: return tr(en: "Charging", zh: "充电中")
        case .full: return tr(en: "Full", zh: "已充满")
        case .notCharging: return tr(en: "Not charging", zh: "未在充电")
        }
    }
    static var externalPower: String { tr(en: "External power", zh: "外接电源") }
    static func connected(_ connected: Bool) -> String {
        connected ? tr(en: "Connected", zh: "已连接") : tr(en: "Not connected", zh: "未连接")
    }
    static var deviceFullChargeCapacity: String { tr(en: "Full-charge capacity", zh: "实际满充容量") }
    static var deviceCapacityRatio: String { tr(en: "Capacity ratio · estimate", zh: "容量比 · 估算") }
}
