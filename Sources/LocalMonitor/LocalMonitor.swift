import AppKit
import SwiftUI
import Combine
import BatteryCore
import IOKit.ps
import Darwin
import SystemCore
import DeviceCore

@MainActor
final class BatteryModel: ObservableObject {
    @Published private(set) var snapshot: BatterySnapshot
    private let read: () -> BatterySnapshot
    private(set) var readCount = 1

    init(read: @escaping () -> BatterySnapshot = { BatteryReader().read() }) {
        self.read = read
        self.snapshot = read()
    }
    func refresh() { snapshot = read(); readCount += 1 }

    var status: String { BatteryPresentation.status(snapshot) }
    var percentage: String { snapshot.percentage.map { "\($0)%" } ?? "—" }
}

@MainActor
struct BatteryDetails: View {
    @ObservedObject var model: BatteryModel
    let quit: () -> Void
    private func number(_ value: Double, format: String, suffix: String) -> String {
        String(format: format, value) + suffix
    }
    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).monospacedDigit().multilineTextAlignment(.trailing)
        }.font(.system(size: 12))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("电池监控").font(.headline)
                    Text(model.status).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Text(model.percentage).font(.system(size: 32, weight: .medium, design: .rounded)).monospacedDigit()
            }
            if let percentage = model.snapshot.percentage {
                ProgressView(value: Double(percentage), total: 100)
                    .tint(percentage <= 20 ? .orange : .green)
                    .accessibilityLabel("电量").accessibilityValue("\(percentage)%")
            }
            Divider()
            VStack(spacing: 8) {
                if let condition = model.snapshot.condition { row("系统健康状态", condition) }
                if let reportedHealth = model.snapshot.reportedHealthPercent {
                    row("系统最大容量", number(reportedHealth, format: "%.0f", suffix: "%"))
                }
                if let health = model.snapshot.healthPercent { row("容量比 · 估算健康", number(health, format: "%.1f", suffix: "%")) }
                if let maximum = model.snapshot.maximumCapacityMAh { row("当前最大容量", "\(maximum) mAh") }
                if let design = model.snapshot.designCapacityMAh { row("设计容量", "\(design) mAh") }
                if let cycles = model.snapshot.cycleCount { row("循环次数", String(cycles)) }
            }
            Divider()
            VStack(spacing: 8) {
                if let temperature = model.snapshot.temperatureCelsius { row("电池温度", number(temperature, format: "%.1f", suffix: " °C")) }
                if let voltage = model.snapshot.voltageVolts { row("电压", number(voltage, format: "%.3f", suffix: " V")) }
                if let current = model.snapshot.amperageMA { row("电流", number(current, format: "%.0f", suffix: " mA")) }
                if let power = model.snapshot.powerWatts { row("功率 · 电池侧估算", number(power, format: "%+.2f", suffix: " W")) }
            }
            if !model.snapshot.readErrors.isEmpty {
                Text("部分系统数据读取失败，请尝试刷新。缺失值不会当作零。")
                    .font(.system(size: 11)).foregroundStyle(.orange)
            }
            Text("功率正值为流入电池，负值为放电；不是整机功耗或充电器功率。容量比可能高于 100%。")
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack {
                Text(model.snapshot.timestamp, style: .time).monospacedDigit()
                Text("· 仅事件与手动刷新")
            }.font(.system(size: 10)).foregroundStyle(.secondary)
            Text("本机只读 · 不保存历史 · 不联网")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let model = BatteryModel()
    private let monitor = MonitorModel()
    private var item: NSStatusItem!
    private let popover = NSPopover()
    private var wakeObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    private var powerModeObserver: NSObjectProtocol?
    private var changeObserver: AnyCancellable?
    private var powerSource: CFRunLoopSource?
    private var pendingPowerRefresh: DispatchWorkItem?
    private var smokeMode: Bool { CommandLine.arguments.contains("--smoke-test") }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.target = self
            button.action = #selector(togglePanel)
            button.sendAction(on: [.leftMouseUp])
            button.setAccessibilityLabel("本机监控")
        }
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: MonitorPanel(battery: model, monitor: monitor) { NSApp.terminate(nil) })
        popover.contentSize = NSSize(width: 420, height: 650)
        changeObserver = model.$snapshot.sink { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.updateStatus() }
        }
        powerSource = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor [weak delegate] in delegate?.schedulePowerRefresh() }
        }, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue()
        if let powerSource { CFRunLoopAddSource(CFRunLoopGetMain(), powerSource, .commonModes) }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.model.refresh()
                self.monitor.updateVisibility(self.popover.isShown)
            }
        }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.monitor.updateVisibility(false, sleeping: true) }
        }
        powerModeObserver = NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.monitor.updateVisibility(self.popover.isShown)
            }
        }
        updateStatus()
        if CommandLine.arguments.contains("--device-layout-test") {
            Task { @MainActor [self] in
                let devices = await DeviceReader().read(timeout: 5)
                print("DEVICE_LAYOUT status=\(devices.status.rawValue) count=\(devices.devices.count)")
                var success = devices.status == .available && !devices.devices.isEmpty
                if let index = CommandLine.arguments.firstIndex(of: "--render-preview"), CommandLine.arguments.indices.contains(index + 1) {
                    success = renderPreview(to: CommandLine.arguments[index + 1], devices: devices) && success
                }
                finishSmoke(success: success)
            }
            return
        }
        if CommandLine.arguments.contains("--sampling-test") {
            runSamplingTest()
            return
        }
        if smokeMode {
            print("UI_SMOKE_READY statusItem=\(item?.button != nil) percentage=\(model.percentage) state=\(model.status) powerEvents=\(powerSource != nil) temperature=\(String(describing: model.snapshot.temperatureCelsius))")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [self] in
                var success = item?.button != nil && powerSource != nil
                if let index = CommandLine.arguments.firstIndex(of: "--render-preview") {
                    if CommandLine.arguments.indices.contains(index + 1) {
                        success = renderPreview(to: CommandLine.arguments[index + 1]) && success
                    } else {
                        print("UI_PREVIEW_FAILED missing output path")
                        success = false
                    }
                }
                if CommandLine.arguments.contains("--interaction-test") {
                    togglePanel()
                    print("UI_PANEL_OPEN shown=\(popover.isShown)")
                    success = success && popover.isShown
                    model.refresh()
                    popover.performClose(nil)
                    // Closing is animated; isShown stays true until AppKit completes it.
                    let precedingChecksPassed = success
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [self] in
                        print("UI_PANEL_CLOSED shown=\(popover.isShown)")
                        finishSmoke(success: precedingChecksPassed && !popover.isShown)
                    }
                    return
                }
                finishSmoke(success: success)
            }
        }
    }
    private func runSamplingTest() {
        togglePanel()
        let initialBatteryReads = model.readCount
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) { [self] in
            let visibleReads = monitor.systemReadCount
            var success = visibleReads >= 2 && monitor.system != nil
            if let index = CommandLine.arguments.firstIndex(of: "--render-preview"), CommandLine.arguments.indices.contains(index + 1) {
                success = renderPreview(to: CommandLine.arguments[index + 1]) && success
            }
            popover.performClose(nil)
            monitor.stop()
            let checks = success
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) { [self] in
                let stopped = monitor.systemReadCount == visibleReads && !monitor.isSampling
                print("SAMPLING_TEST visibleSystemReads=\(visibleReads) hiddenSystemReads=\(monitor.systemReadCount - visibleReads) batteryReadsDuringTest=\(model.readCount - initialBatteryReads) batteryTimer=false deviceTimer=false")
                finishSmoke(success: checks && stopped)
            }
        }
    }
    private func schedulePowerRefresh() {
        guard pendingPowerRefresh == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingPowerRefresh = nil
            self.model.refresh()
        }
        pendingPowerRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
    func popoverDidClose(_ notification: Notification) { monitor.stop() }
    private func finishSmoke(success: Bool) {
        applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        print("UI_SMOKE_RESULT success=\(success)")
        fflush(stdout)
        exit(success ? 0 : 1)
    }
    // Renders this app's own SwiftUI view only. It never captures the user's desktop.
    private func renderPreview(to path: String, devices: DeviceSnapshot? = nil) -> Bool {
        let previewMonitor: MonitorModel
        if let devices {
            previewMonitor = MonitorModel(initialDevices: devices)
            previewMonitor.page = .devices
        } else { previewMonitor = monitor }
        let view = NSHostingView(rootView: MonitorPanel(battery: model, monitor: previewMonitor) {}
            .environment(\.colorScheme, .light)
            .background(Color(nsColor: .windowBackgroundColor)))
        view.appearance = NSAppearance(named: .aqua)
        let size = view.fittingSize
        view.frame = NSRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            print("UI_PREVIEW_FAILED bitmap unavailable")
            return false
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            print("UI_PREVIEW_FAILED PNG encoding")
            return false
        }
        do {
            try data.write(to: URL(fileURLWithPath: path))
            print("UI_PREVIEW_WRITTEN width=\(Int(size.width)) height=\(Int(size.height)) path=\(path)")
            return true
        } catch {
            print("UI_PREVIEW_FAILED \(error.localizedDescription)")
            return false
        }
    }
    private func updateStatus() {
        guard let button = item?.button else { return }
        button.title = " " + model.percentage
        button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        let symbol = BatteryPresentation.symbol(model.snapshot)
        let batteryImage = NSImage(systemSymbolName: symbol, accessibilityDescription: model.status)
            ?? NSImage(systemSymbolName: "battery.0", accessibilityDescription: model.status)
        if model.snapshot.isCharging == true, let batteryImage,
           let bolt = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "正在充电") {
            // SF Symbols provides only battery.100.bolt, not per-level bolt variants.
            // Compose the actual battery level with a separate charging indicator.
            let image = NSImage(size: NSSize(width: 32, height: 14), flipped: false) { _ in
                batteryImage.draw(in: NSRect(x: 0, y: 1, width: 23, height: 12))
                bolt.draw(in: NSRect(x: 25, y: 1, width: 7, height: 12))
                return true
            }
            image.isTemplate = true
            button.image = image
        } else { button.image = batteryImage }
        button.imagePosition = .imageLeading
        button.toolTip = "本机监控 · \(model.status) · \(model.percentage)"
        button.setAccessibilityValue("\(model.percentage)，\(model.status)")
    }
    @objc private func togglePanel() {
        guard let button = item.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else {
            model.refresh()
            // Accessory apps launched in the background must activate on an explicit click,
            // otherwise a transient popover can dismiss immediately before accepting input.
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            monitor.updateVisibility(true)
        }
    }
    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
        pendingPowerRefresh?.cancel()
        pendingPowerRefresh = nil
        if let powerSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .commonModes)
            CFRunLoopSourceInvalidate(powerSource)
            self.powerSource = nil
        }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
        if let powerModeObserver { NotificationCenter.default.removeObserver(powerModeObserver) }
        if let item { NSStatusBar.system.removeStatusItem(item) }
    }
}

#if !BATTERY_UI_TESTS
@main
struct LocalMonitorMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
#endif
