import Foundation
import AppKit
import BatteryCore

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
    check(SamplingPolicy.batteryPollingInterval == nil, "battery never polled")
    check(SamplingPolicy.devicePollingInterval == nil, "devices never polled")
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
}
