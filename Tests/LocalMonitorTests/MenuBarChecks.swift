import Foundation
import AppKit
import BatteryCore
import SystemCore

// Menu bar metric rules: default and stored choice, status item content for every metric and
// state in both languages, glyph fallbacks, and the background sampler's lifecycle.
@MainActor
func runMenuBarChecks(_ check: (Bool, String) -> Void) {
    // Default and stored choice.
    check(MenuBarMetric.defaultMetric(hasBattery: true) == .battery, "default is battery with a battery")
    check(MenuBarMetric.defaultMetric(hasBattery: false) == .cpu, "default is CPU without a battery")
    check(MenuBarMetric.resolve(stored: nil, hasBattery: false) == .cpu, "nothing stored uses the default")
    check(MenuBarMetric.resolve(stored: "memory", hasBattery: true) == .memory, "stored choice wins")
    check(MenuBarMetric.resolve(stored: "iconOnly", hasBattery: false) == .iconOnly, "stored icon only")
    check(MenuBarMetric.resolve(stored: "bogus", hasBattery: true) == .battery, "invalid stored value falls back")
    check(MenuBarMetric.allCases.map { $0.rawValue } == ["battery", "cpu", "memory", "iconOnly"], "raw values are stable")
    check(MenuBarMetric.allCases.filter { $0.needsLoadSampling } == [.cpu, .memory], "only CPU and memory sample")

    let suite = "local-monitor-ui-tests-\(UUID().uuidString)"
    if let defaults = UserDefaults(suiteName: suite) {
        let settings = MenuBarSettings(defaults: defaults, hasBattery: false)
        check(settings.metric == .cpu && defaults.string(forKey: MenuBarSettings.defaultsKey) == nil,
              "default choice is not written")
        settings.select(.memory)
        check(settings.metric == .memory && defaults.string(forKey: MenuBarSettings.defaultsKey) == "memory",
              "explicit choice is stored")
        check(MenuBarSettings(defaults: defaults, hasBattery: true).metric == .memory, "stored choice is read back")
        let overridden = MenuBarSettings(defaults: defaults, hasBattery: true, override: .iconOnly)
        check(overridden.metric == .iconOnly, "harness override applies")
        overridden.select(.battery)
        check(overridden.metric == .battery && defaults.string(forKey: MenuBarSettings.defaultsKey) == "memory",
              "harness override is never persisted")
        defaults.removePersistentDomain(forName: suite)
    } else {
        check(false, "test defaults suite available")
    }
    check(HarnessOptions(arguments: ["app", "--menu-bar-metric", "cpu"]).menuBarMetric == .cpu, "--menu-bar-metric parsed")
    check(HarnessOptions(arguments: ["app", "--menu-bar-metric", "gpu"]).menuBarMetric == nil, "unknown --menu-bar-metric ignored")
    check(HarnessOptions(arguments: ["app"]).menuBarMetric == nil, "no override by default")
    check(HarnessOptions(arguments: ["app", "--smoke-test", "--preview-fixture"]).previewFixture
            && !HarnessOptions(arguments: ["app", "--smoke-test"]).previewFixture, "--preview-fixture parsed")

    // Percent formatting: whole numbers, clamped, nothing for invalid values.
    check(StatusItemPresentation.wholePercent(23.4) == "23%", "rounds down")
    check(StatusItemPresentation.wholePercent(23.5) == "24%", "rounds half up")
    check(StatusItemPresentation.wholePercent(0) == "0%" && StatusItemPresentation.wholePercent(100) == "100%", "bounds")
    check(StatusItemPresentation.wholePercent(-3) == "0%" && StatusItemPresentation.wholePercent(140) == "100%", "clamped")
    check(StatusItemPresentation.wholePercent(nil) == nil && StatusItemPresentation.wholePercent(Double.nan) == nil
            && StatusItemPresentation.wholePercent(Double.infinity) == nil, "invalid values have no percent")

    // Glyph candidates resolve on this system.
    for (name, symbols) in [("cpu", StatusItemPresentation.cpuSymbols), ("memory", StatusItemPresentation.memorySymbols)] {
        check(NSImage(systemSymbolName: symbols[0], accessibilityDescription: nil) != nil, "\(name) glyph resolves: \(symbols[0])")
        check(StatusItemGlyph.firstAvailable(symbols)?.name == symbols[0], "\(name) resolves to its first glyph")
        check(!symbols.contains { $0.hasPrefix("battery") }, "\(name) never shows a battery glyph")
    }

    let present = BatterySnapshot(isPresent: true, percentage: 80, powerSource: "AC Power", isCharging: true)
    let absent = BatterySnapshot(isPresent: false, availability: .absent)
    let unreadable = BatterySnapshot(isPresent: false, availability: .unknown, readErrors: [.registryUnavailable])
    let firstLoad = SystemLoadSample(timestamp: Date(), cpuUsagePercent: nil, memoryUsedBytes: 6, memoryTotalBytes: 10)
    let load = SystemLoadSample(timestamp: Date(), cpuUsagePercent: 23.4, memoryUsedBytes: 6, memoryTotalBytes: 10)
    let noMemory = SystemLoadSample(timestamp: Date(), cpuUsagePercent: 5, memoryUsedBytes: nil, memoryTotalBytes: nil)

    for language in AppLanguage.allCases {
        L10n.language = language
        let tag = language.rawValue

        // Battery mode reuses the battery rules, including the neutral gauge without a battery.
        let battery = StatusItemPresentation.content(metric: .battery, battery: present, load: load)
        check(battery == StatusItemContent(symbols: BatteryPresentation.statusItemSymbols(present),
                                           title: " 80%", toolTip: BatteryPresentation.statusItemToolTip(present),
                                           accessibilityValue: BatteryPresentation.statusItemAccessibilityValue(present),
                                           showsChargingIndicator: true),
              "battery mode follows the battery rules (\(tag))")
        let noBattery = StatusItemPresentation.content(metric: .battery, battery: absent, load: load)
        check(noBattery.symbols == BatteryPresentation.noBatterySymbols && noBattery.title == ""
                && noBattery.toolTip == L10n.appName && !noBattery.showsChargingIndicator,
              "battery mode without a battery falls back to the neutral gauge (\(tag))")
        let failed = StatusItemPresentation.content(metric: .battery, battery: unreadable, load: nil)
        check(failed.symbols.first == "battery.0" && failed.title == " —", "battery read failure stays a battery (\(tag))")

        // CPU.
        let cpu = StatusItemPresentation.content(metric: .cpu, battery: present, load: load)
        check(cpu.symbols == StatusItemPresentation.cpuSymbols && cpu.title == " 23%" && !cpu.showsChargingIndicator,
              "cpu glyph and title (\(tag))")
        check(cpu.toolTip == L10n.statusItemCPUToolTip(percentage: "23%") && cpu.toolTip.contains("23%")
                && cpu.toolTip.hasPrefix(L10n.appName), "cpu tooltip (\(tag))")
        check(cpu.accessibilityValue == L10n.statusItemCPUAccessibilityValue(percentage: "23%"), "cpu a11y (\(tag))")
        for pending in [nil, firstLoad] as [SystemLoadSample?] {
            let waiting = StatusItemPresentation.content(metric: .cpu, battery: absent, load: pending)
            check(waiting.title == StatusItemPresentation.placeholderTitle && waiting.title == " –%",
                  "cpu placeholder before the first delta (\(tag))")
            check(waiting.symbols == StatusItemPresentation.cpuSymbols, "cpu placeholder keeps the glyph (\(tag))")
            check(waiting.toolTip == L10n.statusItemCPUToolTip(percentage: nil)
                    && waiting.accessibilityValue == L10n.statusItemCPUAccessibilityValue(percentage: nil),
                  "cpu placeholder tooltip and a11y (\(tag))")
        }

        // Memory.
        let memory = StatusItemPresentation.content(metric: .memory, battery: absent, load: firstLoad)
        check(memory.symbols == StatusItemPresentation.memorySymbols && memory.title == " 60%",
              "memory shows the used percentage from the first read (\(tag))")
        check(memory.toolTip == L10n.statusItemMemoryToolTip(percentage: "60%")
                && memory.accessibilityValue == L10n.statusItemMemoryAccessibilityValue(percentage: "60%"),
              "memory tooltip and a11y (\(tag))")
        let memoryMissing = StatusItemPresentation.content(metric: .memory, battery: absent, load: noMemory)
        check(memoryMissing.title == " –%" && memoryMissing.toolTip == L10n.statusItemMemoryToolTip(percentage: nil),
              "memory placeholder when not read (\(tag))")

        // Icon only: neutral glyph, no number, even with a charging battery.
        let icon = StatusItemPresentation.content(metric: .iconOnly, battery: present, load: load)
        check(icon == StatusItemContent(symbols: BatteryPresentation.noBatterySymbols, title: "", toolTip: L10n.appName,
                                        accessibilityValue: L10n.appName, showsChargingIndicator: false),
              "icon only (\(tag))")

        // Layout.
        check(StatusItemPresentation.layout(title: " 23%", hasGlyph: true) == StatusItemLayout(title: " 23%", image: .imageLeading),
              "glyph and title (\(tag))")
        check(StatusItemPresentation.layout(title: "", hasGlyph: true) == StatusItemLayout(title: "", image: .imageOnly),
              "glyph alone (\(tag))")
        check(StatusItemPresentation.layout(title: "", hasGlyph: false) == StatusItemLayout(title: L10n.appName, image: .titleOnly),
              "app name when nothing else shows (\(tag))")
        check(StatusItemPresentation.layout(title: " 23%", hasGlyph: false) == StatusItemLayout(title: " 23%", image: .titleOnly),
              "title alone without a glyph (\(tag))")
        check(MenuBarMetric.allCases.allSatisfy { !$0.label.isEmpty }, "menu labels (\(tag))")
    }

    L10n.language = .english
    check(L10n.statusItemCPUToolTip(percentage: "23%") == "Local Monitor · CPU usage 23%", "en cpu tooltip")
    check(L10n.statusItemCPUToolTip(percentage: nil) == "Local Monitor · CPU usage · measuring…", "en cpu tooltip pending")
    check(L10n.statusItemCPUAccessibilityValue(percentage: "23%") == "CPU usage 23%", "en cpu a11y")
    check(L10n.statusItemMemoryToolTip(percentage: "60%") == "Local Monitor · Memory used 60%", "en memory tooltip")
    check(L10n.statusItemMemoryAccessibilityValue(percentage: nil) == "Memory used, measuring", "en memory a11y pending")
    check(MenuBarMetric.allCases.map { $0.label } == ["Battery", "CPU Usage", "Memory Usage", "Icon Only"], "en menu labels")
    check(L10n.menuBarShows == "Menu Bar Shows", "en menu title")
    L10n.language = .simplifiedChinese
    check(L10n.statusItemCPUToolTip(percentage: "23%") == "本机监控 · CPU 使用率 23%", "zh cpu tooltip")
    check(L10n.statusItemCPUToolTip(percentage: nil) == "本机监控 · CPU 使用率 · 测量中…", "zh cpu tooltip pending")
    check(L10n.statusItemCPUAccessibilityValue(percentage: "23%") == "CPU 使用率 23%", "zh cpu a11y")
    check(L10n.statusItemMemoryToolTip(percentage: "60%") == "本机监控 · 内存已用 60%", "zh memory tooltip")
    check(L10n.statusItemMemoryAccessibilityValue(percentage: nil) == "内存已用，测量中", "zh memory a11y pending")
    check(MenuBarMetric.allCases.map { $0.label } == ["电池", "CPU 使用率", "内存使用", "仅图标"], "zh menu labels")
    check(L10n.menuBarShows == "菜单栏显示", "zh menu title")

    // Sampler lifecycle: runs only for CPU / memory, pauses for sleep, never restarts after stop.
    let sampler = LoadSampler()
    check(!sampler.isRunning && sampler.sample == nil, "sampler idle at start")
    sampler.update(metric: .battery)
    check(!sampler.isRunning && sampler.interval == nil, "battery mode does not sample")
    sampler.update(metric: .cpu)
    let expected = SamplingPolicy.menuBarInterval(metric: .cpu, isSleeping: false,
                                                  lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
    check(sampler.isRunning && sampler.interval == expected, "cpu mode samples")
    sampler.setSleeping(true)
    check(!sampler.isRunning, "sampling pauses across sleep")
    sampler.setSleeping(false)
    check(sampler.isRunning, "sampling resumes on wake")
    sampler.update(metric: .iconOnly)
    check(!sampler.isRunning && sampler.sample == nil, "icon only stops sampling and clears the value")
    sampler.update(metric: .memory)
    check(sampler.isRunning, "memory mode samples")
    sampler.stop()
    check(!sampler.isRunning, "stop ends sampling")
    sampler.update(metric: .cpu)
    sampler.powerStateChanged()
    check(!sampler.isRunning, "nothing restarts after stop")
}
