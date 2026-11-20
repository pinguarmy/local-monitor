import Foundation
import AppKit
import BatteryCore
import DeviceCore

/// Standalone UI test runner (compiled with -D BATTERY_UI_TESTS by scripts/test-direct.sh).
/// Every check block sets `L10n.language` itself; nothing depends on the machine's locale.
@main
struct PresentationRunner {
    @MainActor static func main() {
        var assertions = 0
        var failures = 0
        func check(_ value: Bool, _ name: String) {
            assertions += 1
            if !value { failures += 1; print("FAIL \(name)") }
        }
        runBatteryPresentationChecks(check)
        runSamplingPolicyChecks(check)
        runModelChecks(check)
        runLocalizationChecks(check)
        runPanelLayoutChecks(check)
        runVisibleMetricChecks(check)
        runBatteryRowChecks(check)
        runDeviceStatusChecks(check)
        runMenuBarChecks(check)
        runDeviceNameChecks(check)
        print("UI presentation/model: \(assertions) assertions, \(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }
}

private func sample(_ percent: Int?, charging: Bool = false) -> BatterySnapshot {
    BatterySnapshot(isPresent: true, percentage: percent, powerSource: "AC Power", isCharging: charging)
}

@MainActor
func runBatteryPresentationChecks(_ check: (Bool, String) -> Void) {
    for (percentage, level) in [(0, 0), (5, 0), (12, 0), (13, 25), (37, 25), (38, 50), (62, 50), (63, 75), (80, 75), (87, 75), (88, 100), (100, 100)] {
        for charging in [false, true] {
            let symbol = BatteryPresentation.symbol(sample(percentage, charging: charging))
            check(symbol == "battery.\(level)", "symbol \(percentage) charging=\(charging)")
            check(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil, "system symbol exists: \(symbol)")
        }
    }
    check(NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil) != nil, "charging indicator exists")
    check(BatteryPresentation.symbol(sample(nil)) == "battery.0", "unknown icon")

    // Status item for a Mac without a battery: neutral glyph that resolves, no title, app name only.
    let absent = BatterySnapshot(isPresent: false, availability: .absent)
    let unreadable = BatterySnapshot(isPresent: false, availability: .unknown, readErrors: [.registryUnavailable])
    let chosen = BatteryPresentation.noBatterySymbols[0]
    check(NSImage(systemSymbolName: chosen, accessibilityDescription: nil) != nil, "no-battery glyph resolves: \(chosen)")
    check(BatteryPresentation.statusItemSymbols(absent) == BatteryPresentation.noBatterySymbols, "absent uses neutral glyphs")
    check(StatusItemGlyph.firstAvailable(BatteryPresentation.statusItemSymbols(absent))?.name == chosen,
          "absent resolves to the first neutral glyph")
    check(!BatteryPresentation.statusItemSymbols(absent).contains { $0.hasPrefix("battery") }, "absent never shows a battery glyph")
    check(BatteryPresentation.statusItemSymbols(unreadable).first == "battery.0", "read failure keeps a battery glyph")
    check(StatusItemGlyph.firstAvailable(BatteryPresentation.statusItemSymbols(unreadable)) != nil, "read failure glyph resolves")
    check(StatusItemGlyph.firstAvailable(["no.such.symbol.local-monitor", "battery.0"])?.name == "battery.0",
          "glyph fallback skips unknown names")
    check(BatteryPresentation.statusItemTitle(absent) == "", "absent has no title")
    check(BatteryPresentation.statusItemTitle(unreadable) == " —", "read failure title stays distinguishable")
    check(BatteryPresentation.statusItemTitle(sample(80)) == " 80%", "present title")

    for language in AppLanguage.allCases {
        L10n.language = language
        check(BatteryPresentation.statusItemToolTip(absent) == L10n.appName, "absent tooltip is app name (\(language.rawValue))")
        check(BatteryPresentation.statusItemAccessibilityValue(absent) == L10n.appName, "absent a11y value is app name (\(language.rawValue))")
        check(BatteryPresentation.statusItemToolTip(unreadable).contains(L10n.batteryReadFailed), "read failure tooltip (\(language.rawValue))")
        check(BatteryPresentation.statusItemToolTip(sample(80)).contains("80%"), "present tooltip has percentage (\(language.rawValue))")
    }

    L10n.language = .simplifiedChinese
    check(BatteryPresentation.status(sample(80)) == "已接电 · 未充电", "zh AC not charging")
    check(BatteryPresentation.status(sample(80, charging: true)) == "正在充电", "zh charging")
    check(BatteryPresentation.status(BatterySnapshot(isPresent: true, isCharged: true)) == "已充满", "zh full")
    check(BatteryPresentation.status(BatterySnapshot(isPresent: true, powerSource: "Battery Power")) == "使用电池", "zh battery power")
    check(BatteryPresentation.status(BatterySnapshot(isPresent: true)) == "电源状态未知", "zh power unknown")
    check(BatteryPresentation.status(absent) == "未检测到内置电池", "zh absent")
    check(BatteryPresentation.status(unreadable) == "电池数据读取失败", "zh read failure is not absent")
    check(BatteryPresentation.statusItemAccessibilityValue(sample(80)) == "80%，已接电 · 未充电", "zh a11y value")

    L10n.language = .english
    check(BatteryPresentation.status(sample(80)) == "Plugged in · not charging", "en AC not charging")
    check(BatteryPresentation.status(sample(80, charging: true)) == "Charging", "en charging")
    check(BatteryPresentation.status(BatterySnapshot(isPresent: true, isCharged: true)) == "Fully charged", "en full")
    check(BatteryPresentation.status(BatterySnapshot(isPresent: true, powerSource: "Battery Power")) == "On battery", "en battery power")
    check(BatteryPresentation.status(BatterySnapshot(isPresent: true)) == "Power source unknown", "en power unknown")
    check(BatteryPresentation.status(absent) == "No internal battery", "en absent")
    check(BatteryPresentation.status(unreadable) == "Couldn't read battery data", "en read failure is not absent")
    check(BatteryPresentation.statusItemToolTip(sample(80)) == "Local Monitor · Plugged in · not charging · 80%", "en tooltip")
    check(BatteryPresentation.statusItemAccessibilityValue(sample(80)) == "80%, Plugged in · not charging", "en a11y value")
}

@MainActor
func runSamplingPolicyChecks(_ check: (Bool, String) -> Void) {
    // Full matrix: page x panel visible x sleeping x low power.
    for page in MonitorPage.allCases {
        for visible in [false, true] {
            for sleeping in [false, true] {
                for lowPower in [false, true] {
                    let interval = SamplingPolicy.systemInterval(panelVisible: visible, page: page, isSleeping: sleeping, lowPower: lowPower)
                    let expected: TimeInterval? = (visible && page == .system && !sleeping) ? (lowPower ? 5 : 2) : nil
                    let name = "page=\(page.rawValue) visible=\(visible) sleeping=\(sleeping) lowPower=\(lowPower)"
                    check(interval == expected, "systemInterval \(name)")
                    // An early second sample exists exactly when a timer exists, and comes before the first tick.
                    let warmUp = SamplingPolicy.warmUpDelay(interval: interval)
                    check((warmUp == nil) == (interval == nil), "warm-up only while sampling \(name)")
                    if let warmUp, let interval { check(warmUp > 0 && warmUp < interval, "warm-up precedes first tick \(name)") }
                }
            }
        }
    }
    check(SamplingPolicy.warmUpDelay(interval: 2) == 1, "warm-up 1 s at the 2 s interval")
    check(SamplingPolicy.warmUpDelay(interval: 5) == 1, "warm-up 1 s in Low Power Mode")
    check(SamplingPolicy.warmUpDelay(interval: 1) == nil, "no warm-up when the interval is already short")
    check(SamplingPolicy.warmUpDelay(interval: nil) == nil, "no warm-up without sampling")

    // Battery tab refresh and Devices tab re-read: only while visible on their own tab and awake.
    let issues: [DeviceReadIssue?] = [nil, .frameworkUnavailable, .subscriptionFailed, .notificationCleanupFailed,
                                      .readInProgress, .deviceUnreadable]
    for page in MonitorPage.allCases {
        for visible in [false, true] {
            for sleeping in [false, true] {
                for lowPower in [false, true] {
                    let name = "page=\(page.rawValue) visible=\(visible) sleeping=\(sleeping) lowPower=\(lowPower)"
                    let shown = visible && !sleeping
                    for hasBattery in [false, true] {
                        let battery = SamplingPolicy.batteryInterval(panelVisible: visible, page: page, isSleeping: sleeping,
                                                                     lowPower: lowPower, hasBattery: hasBattery)
                        let expected: TimeInterval? = (shown && page == .battery && hasBattery) ? (lowPower ? 10 : 5) : nil
                        check(battery == expected, "batteryInterval \(name) hasBattery=\(hasBattery)")
                    }
                    for issue in issues {
                        let devices = SamplingPolicy.deviceInterval(panelVisible: visible, page: page, isSleeping: sleeping,
                                                                    lowPower: lowPower, lastIssue: issue)
                        let expected: TimeInterval? = (shown && page == .devices && !lowPower
                                                       && issue != .notificationCleanupFailed) ? 10 : nil
                        check(devices == expected, "deviceInterval \(name) issue=\(issue?.rawValue ?? "nil")")
                    }
                }
            }
        }
    }
    check(SamplingPolicy.batteryInterval(panelVisible: true, page: .battery, isSleeping: false, lowPower: false, hasBattery: true) == 5,
          "battery refreshes every 5 s while shown")
    check(SamplingPolicy.batteryInterval(panelVisible: true, page: .battery, isSleeping: false, lowPower: true, hasBattery: true) == 10,
          "battery refreshes every 10 s in Low Power Mode")
    check(SamplingPolicy.batteryInterval(panelVisible: false, page: .battery, isSleeping: false, lowPower: false, hasBattery: true) == nil,
          "battery timer stops when the panel closes")
    check(SamplingPolicy.deviceInterval(panelVisible: true, page: .devices, isSleeping: false, lowPower: false, lastIssue: nil) == 10,
          "devices re-read every 10 s while shown")
    check(SamplingPolicy.deviceInterval(panelVisible: true, page: .devices, isSleeping: false, lowPower: true, lastIssue: nil) == nil,
          "devices not re-read in Low Power Mode")
    check(SamplingPolicy.deviceInterval(panelVisible: true, page: .devices, isSleeping: false, lowPower: false,
                                        lastIssue: .notificationCleanupFailed) == nil,
          "devices not re-read after a cleanup failure")

    // Menu bar: only CPU and memory sample, every 3 s (6 s in Low Power Mode), never while asleep.
    for metric in MenuBarMetric.allCases {
        for sleeping in [false, true] {
            for lowPower in [false, true] {
                let interval = SamplingPolicy.menuBarInterval(metric: metric, isSleeping: sleeping, lowPower: lowPower)
                let expected: TimeInterval? = (metric.needsLoadSampling && !sleeping) ? (lowPower ? 6 : 3) : nil
                check(interval == expected, "menuBarInterval metric=\(metric.rawValue) sleeping=\(sleeping) lowPower=\(lowPower)")
                if let interval { check(SamplingPolicy.warmUpDelay(interval: interval) == 1, "menu bar warm-up \(metric.rawValue)") }
            }
        }
    }
    check(SamplingPolicy.menuBarInterval(metric: .battery, isSleeping: false, lowPower: false) == nil, "battery mode never samples")
    check(SamplingPolicy.menuBarInterval(metric: .iconOnly, isSleeping: false, lowPower: false) == nil, "icon only never samples")
    for interval in [2.0, 3, 5, 6, 10] {
        let tolerance = SamplingPolicy.tolerance(interval: interval)
        check(tolerance > 0 && tolerance < interval / 2, "timer tolerance is a small share of \(interval) s")
    }
}

@MainActor
func runModelChecks(_ check: (Bool, String) -> Void) {
    var reads = 0
    let model = BatteryModel(read: {
        reads += 1
        return sample(reads)
    })
    check(reads == 1 && model.snapshot.percentage == 1, "initial read")
    model.refresh()
    check(reads == 2 && model.snapshot.percentage == 2, "injected reader refresh")
    check(model.percentage == "2%", "model percentage text")
    check(BatteryModel(read: { BatterySnapshot(isPresent: false, availability: .absent) }).percentage == "—",
          "smoke marker percentage without a battery")

    // Without a bundle identifier ServiceManagement is never touched and the toggle is hidden.
    let unsupported = LaunchAtLogin(bundleIdentifier: nil)
    check(!unsupported.isSupported && !unsupported.isEnabled, "launch at login unsupported without bundle id")
    unsupported.setEnabled(true)
    check(!unsupported.isEnabled, "unsupported launch at login stays off")

    let monitor = MonitorModel()
    check(monitor.page == .system, "app opens on the System tab")
    check(!monitor.isSampling && monitor.system == nil, "monitor idle until the panel opens")
    check(!monitor.isBatteryTimerRunning && !monitor.isDeviceTimerRunning, "no panel timers until the panel opens")
    check(!monitor.showsDeviceProgress && !monitor.isReadingDevices, "no device read until the Devices tab opens")

    // Battery timer: only on the Battery tab of a visible panel, and only with a battery to read.
    let batteryMonitor = MonitorModel()
    let present = BatteryModel(read: { sample(50) })
    batteryMonitor.battery = present
    batteryMonitor.page = .battery
    batteryMonitor.updateVisibility(true)
    check(batteryMonitor.isBatteryTimerRunning && !batteryMonitor.isSampling && !batteryMonitor.isDeviceTimerRunning,
          "battery tab runs only the battery timer")
    batteryMonitor.updateVisibility(false, sleeping: true)
    check(!batteryMonitor.isBatteryTimerRunning, "battery timer stops while asleep")
    batteryMonitor.updateVisibility(true)
    batteryMonitor.page = .system
    batteryMonitor.pageChanged()
    check(!batteryMonitor.isBatteryTimerRunning && batteryMonitor.isSampling, "leaving the Battery tab stops its timer")
    batteryMonitor.stop()
    check(!batteryMonitor.isBatteryTimerRunning && !batteryMonitor.isSampling, "closing the panel stops every timer")
    let desktopMonitor = MonitorModel()
    let desktopBattery = BatteryModel(read: { BatterySnapshot(isPresent: false, availability: .absent) })
    desktopMonitor.battery = desktopBattery
    desktopMonitor.page = .battery
    desktopMonitor.updateVisibility(true)
    check(!desktopMonitor.isBatteryTimerRunning, "no battery timer without a battery")
    desktopMonitor.stop()
    withExtendedLifetime(present) {}
    withExtendedLifetime(desktopBattery) {}
    // Preview models have no battery model attached and never read.
    let previewMonitor = MonitorModel(initialDevices: nil, initialSystem: nil)
    previewMonitor.page = .battery
    check(!previewMonitor.isBatteryTimerRunning, "preview monitor has no battery timer")
}
