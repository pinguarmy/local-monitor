import Foundation
import BatteryCore
import SystemCore

// Battery tab rules: rows only for a present battery, nil (and non-positive) values hidden,
// footnotes only for rows that are shown.
@MainActor
func runBatteryRowChecks(_ check: (Bool, String) -> Void) {
    let discharging = BatterySnapshot(
        isPresent: true, percentage: 64, powerSource: "Battery Power", isCharging: false,
        condition: "Normal", maximumCapacityMAh: 4300, designCapacityMAh: 4500, healthPercent: 95.6, cycleCount: 210,
        temperatureCelsius: 31.2, voltageVolts: 12.345, amperageMA: -1500, powerWatts: -18.5,
        timeToEmptyMinutes: 85
    )
    let charging = BatterySnapshot(
        isPresent: true, percentage: 40, powerSource: "AC Power", isCharging: true,
        timeToFullChargeMinutes: 120, adapterWatts: 96
    )
    let bare = BatterySnapshot(isPresent: true, percentage: 50, powerSource: "AC Power")
    let absent = BatterySnapshot(isPresent: false, availability: .absent)
    let unreadable = BatterySnapshot(isPresent: false, availability: .unknown, readErrors: [.powerSourcesUnavailable])

    for language in AppLanguage.allCases {
        L10n.language = language
        let tag = language.rawValue

        let dischargeRows = VisibleMetrics.batteryChargeRows(discharging)
        check(dischargeRows == [MetricItem(title: L10n.timeRemaining, value: L10n.duration(minutes: 85))],
              "time remaining only while discharging (\(tag))")
        let chargeRows = VisibleMetrics.batteryChargeRows(charging)
        check(chargeRows == [MetricItem(title: L10n.timeToFull, value: L10n.duration(minutes: 120)),
                             MetricItem(title: L10n.powerAdapter, value: "96 W")],
              "time to full and adapter while charging (\(tag))")
        check(VisibleMetrics.batteryChargeRows(bare).isEmpty, "no charge rows when nil (\(tag))")
        let zeroes = BatterySnapshot(isPresent: true, timeToEmptyMinutes: 0, timeToFullChargeMinutes: -1, adapterWatts: 0)
        check(VisibleMetrics.batteryChargeRows(zeroes).isEmpty, "non-positive estimates hidden (\(tag))")

        let healthRows = VisibleMetrics.batteryHealthRows(discharging)
        check(healthRows.map { $0.title } == [L10n.batteryCondition, L10n.batteryCapacityRatio, L10n.batteryFullChargeCapacity,
                                               L10n.designCapacity, L10n.cycleCount],
              "health rows in order, reported maximum hidden when nil (\(tag))")
        check(healthRows.contains { $0.title == L10n.batteryCapacityRatio && $0.value == "95.6%" }, "capacity ratio value (\(tag))")
        check(healthRows.contains { $0.title == L10n.batteryFullChargeCapacity && $0.value == "4300 mAh" }, "full charge value (\(tag))")
        let electricalRows = VisibleMetrics.batteryElectricalRows(discharging)
        check(electricalRows == [MetricItem(title: L10n.batteryTemperature, value: "31.2 °C"),
                                 MetricItem(title: L10n.voltage, value: "12.345 V"),
                                 MetricItem(title: L10n.current, value: "-1500 mA"),
                                 MetricItem(title: L10n.batteryPower, value: "-18.50 W")],
              "electrical rows (\(tag))")

        check(VisibleMetrics.batteryFootnotes(discharging) == [L10n.batteryPowerFootnote, L10n.capacityRatioFootnote],
              "both footnotes when power and ratio rows are shown (\(tag))")
        check(VisibleMetrics.batteryFootnotes(charging).isEmpty, "no footnotes without power or ratio rows (\(tag))")
        let powerOnly = BatterySnapshot(isPresent: true, powerWatts: 5)
        check(VisibleMetrics.batteryFootnotes(powerOnly) == [L10n.batteryPowerFootnote], "power footnote alone (\(tag))")
        let ratioOnly = BatterySnapshot(isPresent: true, healthPercent: 101)
        check(VisibleMetrics.batteryFootnotes(ratioOnly) == [L10n.capacityRatioFootnote], "ratio footnote alone (\(tag))")

        for snapshot in [absent, unreadable] {
            check(VisibleMetrics.batteryChargeRows(snapshot).isEmpty && VisibleMetrics.batteryHealthRows(snapshot).isEmpty
                    && VisibleMetrics.batteryElectricalRows(snapshot).isEmpty && VisibleMetrics.batteryFootnotes(snapshot).isEmpty,
                  "no rows or footnotes without a readable battery (\(tag), \(snapshot.availability.rawValue))")
        }
        check(BatteryPresentation.percentage(absent) == nil, "absent has no percentage (\(tag))")
        check(!L10n.batteryAbsentTitle.isEmpty && !L10n.batteryAbsentMessage.isEmpty, "absent empty state text (\(tag))")
        check(!L10n.batteryUnknownTitle.isEmpty && !L10n.batteryUnknownMessage.isEmpty, "unknown state text (\(tag))")
        check(L10n.batteryAbsentMessage != L10n.batteryUnknownMessage, "absent and unknown explain differently (\(tag))")
    }

    // Condition: known IOPowerSources strings are translated, anything else passes through.
    let knownConditions: [(String, String)] = [("Good", "良好"), ("Fair", "一般"), ("Poor", "较差"),
                                               ("Check Battery", "检查电池"), ("Permanent Failure", "永久故障")]
    for (raw, chinese) in knownConditions {
        L10n.language = .english
        check(L10n.batteryConditionValue(raw) == raw, "en condition \(raw) shown as is")
        L10n.language = .simplifiedChinese
        check(L10n.batteryConditionValue(raw) == chinese, "zh condition \(raw) translated")
    }
    for language in AppLanguage.allCases {
        L10n.language = language
        for raw in ["Normal", "Service Recommended", "good", ""] {
            check(L10n.batteryConditionValue(raw) == raw, "unknown condition '\(raw)' passes through (\(language.rawValue))")
        }
    }
    L10n.language = .simplifiedChinese
    let poor = BatterySnapshot(isPresent: true, condition: "Poor")
    check(VisibleMetrics.batteryHealthRows(poor).first == MetricItem(title: "系统健康状态", value: "较差"), "zh condition row")
    check(VisibleMetrics.batteryHealthRows(discharging).first == MetricItem(title: "系统健康状态", value: "Normal"),
          "zh unknown condition row unchanged")
    L10n.language = .english
    check(VisibleMetrics.batteryHealthRows(poor).first == MetricItem(title: "Condition", value: "Poor"), "en condition row")

    // The preview fixture populates every Battery tab group, both footnotes included.
    let fixture = PreviewFixtures.battery
    check(fixture.availability == .present && fixture.isCharging == false, "fixture battery is present and discharging")
    check(VisibleMetrics.batteryChargeRows(fixture).map { $0.title } == [L10n.timeRemaining], "fixture time remaining")
    check(VisibleMetrics.batteryHealthRows(fixture).count >= 5, "fixture health rows")
    check(VisibleMetrics.batteryElectricalRows(fixture).count == 4, "fixture electrical rows")
    check(VisibleMetrics.batteryFootnotes(fixture).count == 2, "fixture shows both footnotes")
    let fixtureSystem = PreviewFixtures.system
    check(VisibleMetrics.cpuRows(fixtureSystem.cpu).first?.title == L10n.cpuUsage, "fixture system has CPU usage")
    check(VisibleMetrics.networkRows(fixtureSystem.network).count == 3, "fixture system has network rates")
    check(!VisibleMetrics.memoryRows(fixtureSystem.memory).isEmpty && !VisibleMetrics.diskRows(fixtureSystem.disk).isEmpty
            && !VisibleMetrics.gpuRows(fixtureSystem.gpu).isEmpty, "fixture system fills every group")

    L10n.language = .english
    check(L10n.duration(minutes: 85) == "1 h 25 min", "en duration")
    check(L10n.duration(minutes: 120) == "2 h", "en whole hours")
    check(L10n.duration(minutes: 45) == "45 min", "en minutes only")
    check(VisibleMetrics.batteryChargeRows(discharging).first?.title == "Time remaining", "en time remaining title")
    check(L10n.batteryAbsentMessage == "This Mac has no internal battery.", "en absent message")
    L10n.language = .simplifiedChinese
    check(L10n.duration(minutes: 85) == "1 小时 25 分", "zh duration")
    check(L10n.duration(minutes: 120) == "2 小时", "zh whole hours")
    check(L10n.duration(minutes: 45) == "45 分", "zh minutes only")
    check(VisibleMetrics.batteryChargeRows(charging).last == MetricItem(title: "电源适配器", value: "96 W"), "zh adapter row")
}
