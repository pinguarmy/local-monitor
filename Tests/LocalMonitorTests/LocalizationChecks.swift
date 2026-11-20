import Foundation
import SystemCore
import DeviceCore

// Catalog sanity in both languages, language resolution and harness argument parsing.
@MainActor
func runLocalizationChecks(_ check: (Bool, String) -> Void) {
    // Resolution: --language wins, then the first preferred localization; "zh*" is Chinese, all else English.
    check(AppLanguage.resolve(arguments: ["app"], preferredLocalizations: ["zh-Hans", "en"]) == .simplifiedChinese, "zh-Hans preferred")
    check(AppLanguage.resolve(arguments: ["app"], preferredLocalizations: ["zh_CN"]) == .simplifiedChinese, "zh_CN preferred")
    check(AppLanguage.resolve(arguments: ["app"], preferredLocalizations: ["zh-Hant"]) == .simplifiedChinese, "any zh is Chinese")
    check(AppLanguage.resolve(arguments: ["app"], preferredLocalizations: ["en-GB", "zh-Hans"]) == .english, "first preference wins")
    check(AppLanguage.resolve(arguments: ["app"], preferredLocalizations: ["fr"]) == .english, "other languages fall back to English")
    check(AppLanguage.resolve(arguments: ["app"], preferredLocalizations: []) == .english, "no preference is English")
    check(AppLanguage.resolve(arguments: ["app", "--language", "zh-Hans"], preferredLocalizations: ["en"]) == .simplifiedChinese,
          "--language zh-Hans overrides")
    check(AppLanguage.resolve(arguments: ["app", "--smoke-test", "--language", "en"], preferredLocalizations: ["zh-Hans"]) == .english,
          "--language en overrides")
    check(AppLanguage.resolve(arguments: ["app", "--language"], preferredLocalizations: ["zh-Hans"]) == .simplifiedChinese,
          "--language without a value is ignored")

    // Harness arguments.
    let options = HarnessOptions(arguments: ["app", "--smoke-test", "--render-preview", "out.png", "--preview-page", "battery"])
    check(options.smokeTest && !options.samplingTest && !options.deviceLayoutTest, "harness mode flags")
    check(options.previewPath == "out.png" && options.previewPage == .battery, "preview path and page")
    check(HarnessOptions(arguments: ["app", "--preview-page", "bogus"]).previewPage == nil, "unknown preview page ignored")
    check(HarnessOptions(arguments: ["app", "--render-preview"]).renderPreviewRequested
            && HarnessOptions(arguments: ["app", "--render-preview"]).previewPath == nil, "render preview without path detected")
    for page in MonitorPage.allCases {
        check(HarnessOptions(arguments: ["--preview-page", page.rawValue]).previewPage == page, "preview page \(page.rawValue)")
    }

    // Entries that must exist and differ between languages.
    let translated1: [(String, () -> String)] = [
        ("appName", { L10n.appName }), ("panelBadge", { L10n.panelBadge }), ("pagePickerLabel", { L10n.pagePickerLabel }),
        ("refresh", { L10n.refresh }), ("quit", { L10n.quit }), ("moreMenu", { L10n.moreMenu }),
        ("launchAtLogin", { L10n.launchAtLogin }), ("version", { L10n.version("1.0") }),
        ("pageSystem", { MonitorPage.system.label }), ("pageBattery", { MonitorPage.battery.label }),
        ("pageDevices", { MonitorPage.devices.label }),
        ("samplingEvery", { L10n.systemSamplingEvery(seconds: 2) }), ("samplingPaused", { L10n.systemSamplingPaused }),
        ("batteryRefreshEvery", { L10n.batteryRefreshEvery(seconds: 5) }), ("batteryEventsOnly", { L10n.batteryEventsOnlyCaption }),
        ("devicesCheckEvery", { L10n.devicesCheckEvery(seconds: 10) }), ("devicesPolicy", { L10n.devicesPolicyCaption }),
        ("chargingIndicator", { L10n.chargingIndicator }),
        ("sampling", { L10n.sampling }), ("systemNotSampled", { L10n.systemNotSampled }),
        ("groupMemory", { L10n.groupMemory }), ("groupDisk", { L10n.groupDisk }), ("groupNetwork", { L10n.groupNetwork }),
        ("groupMachine", { L10n.groupMachine }), ("cpuUsage", { L10n.cpuUsage }), ("cpuUsageA11y", { L10n.cpuUsageAccessibility }),
        ("cpuCores", { L10n.cpuCores }), ("coreCounts", { L10n.coreCounts(logical: 8, physical: nil) }), ("cpuLoad", { L10n.cpuLoad }),
        ("gpuModel", { L10n.gpuModel }), ("gpuUtilization", { L10n.gpuUtilization }), ("usedOfTotal", { L10n.usedOfTotal }),
        ("available", { L10n.available }), ("compressed", { L10n.compressed }), ("swap", { L10n.swap }),
    ]
    let translated2: [(String, () -> String)] = [
        ("memoryUsageA11y", { L10n.memoryUsageAccessibility }), ("memoryPressure", { L10n.memoryPressure }),
        ("diskUsageA11y", { L10n.diskUsageAccessibility }), ("download", { L10n.download }), ("upload", { L10n.upload }),
        ("receivedSent", { L10n.receivedSent }), ("uptime", { L10n.uptime }), ("thermalState", { L10n.thermalState }),
        ("lowPowerMode", { L10n.lowPowerMode }), ("on", { L10n.onOff(true) }), ("off", { L10n.onOff(false) }),
        ("batteryReadFailed", { L10n.batteryReadFailed }), ("batteryAbsent", { L10n.batteryAbsent }),
        ("batteryCharging", { L10n.batteryCharging }), ("batteryCharged", { L10n.batteryCharged }),
        ("pluggedInNotCharging", { L10n.batteryPluggedInNotCharging }), ("pluggedInUnknown", { L10n.batteryPluggedInUnknown }),
        ("onBattery", { L10n.batteryOnBattery }), ("powerUnknown", { L10n.batteryPowerUnknown }),
        ("absentTitle", { L10n.batteryAbsentTitle }), ("absentMessage", { L10n.batteryAbsentMessage }),
        ("unknownTitle", { L10n.batteryUnknownTitle }), ("unknownMessage", { L10n.batteryUnknownMessage }),
        ("partialRead", { L10n.batteryPartialReadWarning }), ("batteryLevelA11y", { L10n.batteryLevelAccessibility }),
        ("timeRemaining", { L10n.timeRemaining }), ("timeToFull", { L10n.timeToFull }), ("powerAdapter", { L10n.powerAdapter }),
        ("duration", { L10n.duration(minutes: 61) }), ("condition", { L10n.batteryCondition }),
        ("reportedMaximum", { L10n.batteryReportedMaximum }), ("capacityRatio", { L10n.batteryCapacityRatio }),
    ]
    let translated3: [(String, () -> String)] = [
        ("fullCharge", { L10n.batteryFullChargeCapacity }), ("designCapacity", { L10n.designCapacity }),
        ("cycleCount", { L10n.cycleCount }), ("batteryTemperature", { L10n.batteryTemperature }), ("voltage", { L10n.voltage }),
        ("current", { L10n.current }), ("batteryPower", { L10n.batteryPower }), ("powerFootnote", { L10n.batteryPowerFootnote }),
        ("ratioFootnote", { L10n.capacityRatioFootnote }), ("reading", { L10n.reading }), ("devicesNotRead", { L10n.devicesNotRead }),
        ("deviceNote", { L10n.deviceNote }), ("status", { L10n.status }), ("noDeviceConnected", { L10n.noDeviceConnected }),
        ("unlockAndTrust", { L10n.unlockAndTrustRequired }), ("interfaceUnavailable", { L10n.interfaceUnavailable }),
        ("readTimedOut", { L10n.readTimedOut }), ("availableButEmpty", { L10n.availableButEmptyDetail }),
        ("noDeviceDetail", { L10n.noDeviceDetail }), ("unavailableDetail", { L10n.unavailableDetail }),
        ("timedOutDetail", { L10n.timedOutDetail }), ("stepConnect", { L10n.stepConnectCable }),
        ("stepTrustYourself", { L10n.stepUnlockAndTrustYourself }), ("stepKeepConnected", { L10n.stepKeepConnectedAndUnlock }),
        ("stepConfirmTrust", { L10n.stepConfirmTrust }), ("stepRefresh", { L10n.stepClickRefresh }),
        ("deviceBatteryA11y", { L10n.deviceBatteryAccessibility }), ("osVersion", { L10n.osVersion }),
        ("chargingStatus", { L10n.chargingStatus }), ("externalPower", { L10n.externalPower }),
        ("connected", { L10n.connected(true) }), ("notConnected", { L10n.connected(false) }),
    ]
    let translated4: [(String, () -> String)] = [
        ("deviceFullCharge", { L10n.deviceFullChargeCapacity }), ("deviceCapacityRatio", { L10n.deviceCapacityRatio }),
        ("pressureNormal", { L10n.memoryPressureLevel(.normal) }), ("pressureWarning", { L10n.memoryPressureLevel(.warning) }),
        ("pressureCritical", { L10n.memoryPressureLevel(.critical) }), ("thermalNominal", { L10n.thermalLevel(.nominal) }),
        ("thermalFair", { L10n.thermalLevel(.fair) }), ("thermalSerious", { L10n.thermalLevel(.serious) }),
        ("thermalCritical", { L10n.thermalLevel(.critical) }), ("chargingCharging", { L10n.chargingState(.charging) }),
        ("chargingFull", { L10n.chargingState(.full) }), ("chargingNot", { L10n.chargingState(.notCharging) }),
        ("uptimeValue", { L10n.uptimeValue(days: 1, hours: 2, minutes: 3) }),
        ("menuBarShows", { L10n.menuBarShows }), ("menuBarBattery", { L10n.menuBarMetric(.battery) }),
        ("menuBarCPU", { L10n.menuBarMetric(.cpu) }), ("menuBarMemory", { L10n.menuBarMetric(.memory) }),
        ("menuBarIconOnly", { L10n.menuBarMetric(.iconOnly) }),
        ("cpuToolTip", { L10n.statusItemCPUToolTip(percentage: "23%") }),
        ("cpuToolTipPending", { L10n.statusItemCPUToolTip(percentage: nil) }),
        ("cpuA11y", { L10n.statusItemCPUAccessibilityValue(percentage: "23%") }),
        ("cpuA11yPending", { L10n.statusItemCPUAccessibilityValue(percentage: nil) }),
        ("memoryToolTip", { L10n.statusItemMemoryToolTip(percentage: "60%") }),
        ("memoryToolTipPending", { L10n.statusItemMemoryToolTip(percentage: nil) }),
        ("memoryA11y", { L10n.statusItemMemoryAccessibilityValue(percentage: "60%") }),
        ("memoryA11yPending", { L10n.statusItemMemoryAccessibilityValue(percentage: nil) }),
        ("conditionGood", { L10n.batteryConditionValue("Good") }), ("conditionFair", { L10n.batteryConditionValue("Fair") }),
        ("conditionPoor", { L10n.batteryConditionValue("Poor") }),
        ("conditionCheck", { L10n.batteryConditionValue("Check Battery") }),
        ("conditionFailure", { L10n.batteryConditionValue("Permanent Failure") }),
    ]
    let translated = translated1 + translated2 + translated3 + translated4
    for (name, text) in translated {
        L10n.language = .english
        let english = text()
        L10n.language = .simplifiedChinese
        let chinese = text()
        check(!english.isEmpty && !chinese.isEmpty, "catalog \(name) non-empty")
        check(english != chinese, "catalog \(name) differs between languages")
        check(!containsCJK(english), "catalog \(name) English has no Chinese")
        check(containsCJK(chinese), "catalog \(name) Chinese is Chinese")
    }

    // Product names and units read the same in both languages but must still exist.
    let shared: [(String, () -> String)] = [
        ("groupCPU", { L10n.groupCPU }), ("groupGPU", { L10n.groupGPU }),
        ("iPhone", { L10n.deviceKind(.iPhone) }), ("iPad", { L10n.deviceKind(.iPad) }),
        ("osVersionValue", { L10n.osVersionValue(kind: .iPhone, version: "18.1") }),
        ("perSecond", { L10n.perSecond("1 KB") }), ("pair", { L10n.pair("1", "2") }),
        // The time part follows the system locale, so only presence is asserted.
        ("updated", { L10n.updated(at: Date(timeIntervalSince1970: 0)) }),
    ]
    for (name, text) in shared {
        for language in AppLanguage.allCases {
            L10n.language = language
            check(!text().isEmpty, "catalog \(name) non-empty (\(language.rawValue))")
        }
    }

    L10n.language = .english
    check(MonitorPage.allCases.map { $0.label } == ["System", "Battery", "Devices"], "en tab labels")
    check(L10n.appName == "Local Monitor", "en app name")
    check(L10n.systemSamplingEvery(seconds: 2) == "Every 2 s while open · stops on close", "en sampling caption")
    check(L10n.uptimeValue(days: 1, hours: 3, minutes: 9) == "1 d 3 h", "en uptime with days")
    check(L10n.version("0.3.4") == "Version 0.3.4", "en version item")
    check(L10n.batteryRefreshEvery(seconds: 5) == "Updates every 5 s while shown", "en battery caption")
    check(L10n.devicesCheckEvery(seconds: 10) == "Checks every 10 s while shown", "en devices caption")
    check(!L10n.devicesNotRead.lowercased().contains("never"), "en devices note no longer promises no re-reads")
    for caption in [L10n.batteryRefreshEvery(seconds: 5), L10n.batteryEventsOnlyCaption, L10n.devicesCheckEvery(seconds: 10)] {
        check(!caption.lowercased().contains("no polling"), "en caption '\(caption)' reflects timed refresh")
    }
    L10n.language = .simplifiedChinese
    check(MonitorPage.allCases.map { $0.label } == ["系统", "电池", "设备"], "zh tab labels")
    check(L10n.appName == "本机监控", "zh app name")
    check(L10n.systemSamplingEvery(seconds: 5) == "查看时每5秒 · 关闭即停", "zh sampling caption")
    check(L10n.batteryRefreshEvery(seconds: 10) == "查看时每10秒更新", "zh battery caption")
    check(L10n.devicesCheckEvery(seconds: 10) == "查看时每10秒检查", "zh devices caption")
    check(!L10n.batteryEventsOnlyCaption.contains("无定时轮询"), "zh battery caption reflects timed refresh")
    check(L10n.uptimeValue(days: 1, hours: 3, minutes: 9) == "1 天 3 小时", "zh uptime with days")
}
