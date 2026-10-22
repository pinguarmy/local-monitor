import Foundation
import AppKit
import BatteryCore

@main
struct PresentationRunner {
    @MainActor static func main() {
        var assertions = 0
        var failures = 0
        func check(_ value: Bool, _ name: String) {
            assertions += 1
            if !value { failures += 1; print("FAIL \(name)") }
        }
        func sample(_ percent: Int?, charging: Bool = false) -> BatterySnapshot {
            BatterySnapshot(isPresent: true, percentage: percent, powerSource: "AC Power", isCharging: charging)
        }
        for (percentage, level) in [(0, 0), (5, 0), (12, 0), (13, 25), (37, 25), (38, 50), (62, 50), (63, 75), (80, 75), (87, 75), (88, 100), (100, 100)] {
            for charging in [false, true] {
                let symbol = BatteryPresentation.symbol(sample(percentage, charging: charging))
                check(symbol == "battery.\(level)", "symbol \(percentage) charging=\(charging)")
                check(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil, "system symbol exists: \(symbol)")
            }
        }
        check(NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil) != nil, "charging indicator exists")
        check(BatteryPresentation.symbol(sample(nil)) == "battery.0", "unknown icon")
        check(BatteryPresentation.status(sample(80)) == "已接电 · 未充电", "AC not charging")
        check(BatteryPresentation.status(sample(80, charging: true)) == "正在充电", "charging")
        check(BatteryPresentation.status(BatterySnapshot(isPresent: true, isCharged: true)) == "已充满", "full")
        check(BatteryPresentation.status(BatterySnapshot(isPresent: true, powerSource: "Battery Power")) == "使用电池", "battery power")
        check(BatteryPresentation.status(BatterySnapshot(isPresent: false, availability: .absent)) == "未检测到内置电池", "absent")
        check(BatteryPresentation.status(BatterySnapshot(isPresent: false, availability: .unknown)) == "电池数据读取失败", "read failure is not absent")
        check(MonitorPage.allCases.count == 3, "three pages")
        check(MonitorPage.system.label == "系统", "system label")
        check(MonitorPage.battery.label == "电池", "battery label")
        check(MonitorPage.devices.label == "设备", "devices label")
        // Full matrix: page x panel visible x sleeping x low power.
        for page in MonitorPage.allCases {
            for visible in [false, true] {
                for sleeping in [false, true] {
                    for lowPower in [false, true] {
                        let interval = SamplingPolicy.systemInterval(panelVisible: visible, page: page, isSleeping: sleeping, lowPower: lowPower)
                        let expected: TimeInterval? = (visible && page == .system && !sleeping) ? (lowPower ? 5 : 2) : nil
                        check(interval == expected, "systemInterval page=\(page.rawValue) visible=\(visible) sleeping=\(sleeping) lowPower=\(lowPower)")
                    }
                }
            }
        }
        check(SamplingPolicy.batteryPollingInterval == nil, "battery never polled")
        check(SamplingPolicy.devicePollingInterval == nil, "devices never polled")
        var reads = 0
        let model = BatteryModel(read: {
            reads += 1
            return sample(reads)
        })
        check(reads == 1 && model.snapshot.percentage == 1, "initial read")
        model.refresh()
        check(reads == 2 && model.snapshot.percentage == 2, "injected reader refresh")
        runPanelLayoutChecks(check)
        runVisibleMetricChecks(check)
        print("UI presentation/model: \(assertions) assertions, \(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }
}
