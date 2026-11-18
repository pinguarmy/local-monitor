import AppKit
import SwiftUI
import Darwin
import DeviceCore

/// Launch arguments of the smoke / diagnostics harness. CI and the owner's scripts parse the
/// stdout markers printed below (UI_SMOKE_READY, UI_SMOKE_RESULT success=, UI_PREVIEW_WRITTEN,
/// SAMPLING_TEST, DEVICE_LAYOUT), so their formats must not change.
///
/// --smoke-test, --interaction-test, --sampling-test, --device-layout-test,
/// --render-preview <path>, --preview-page system|battery|devices, --language en|zh-Hans
/// (`--language` is read by `AppLanguage.launchDefault()`).
struct HarnessOptions {
    let arguments: [String]

    init(arguments: [String] = CommandLine.arguments) { self.arguments = arguments }

    var smokeTest: Bool { arguments.contains("--smoke-test") }
    var interactionTest: Bool { arguments.contains("--interaction-test") }
    var samplingTest: Bool { arguments.contains("--sampling-test") }
    var deviceLayoutTest: Bool { arguments.contains("--device-layout-test") }
    var renderPreviewRequested: Bool { arguments.contains("--render-preview") }
    var previewPath: String? { value(after: "--render-preview") }
    /// Which tab `--render-preview` renders; nil keeps each mode's default.
    var previewPage: MonitorPage? { value(after: "--preview-page").flatMap { MonitorPage(rawValue: $0) } }

    func value(after flag: String) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}

extension AppDelegate {
    func startHarnessIfRequested() {
        let options = HarnessOptions()
        if options.deviceLayoutTest {
            Task { @MainActor [self] in
                let devices = await DeviceReader().read(timeout: 5)
                print("DEVICE_LAYOUT status=\(devices.status.rawValue) count=\(devices.devices.count)")
                var success = devices.status == .available && !devices.devices.isEmpty
                if let path = options.previewPath {
                    success = renderPreview(to: path, page: options.previewPage ?? .devices, devices: devices) && success
                }
                finishSmoke(success: success)
            }
            return
        }
        if options.samplingTest {
            runSamplingTest(options)
            return
        }
        if options.smokeTest {
            runSmokeTest(options)
        }
    }

    private func runSmokeTest(_ options: HarnessOptions) {
        print("UI_SMOKE_READY statusItem=\(item?.button != nil) percentage=\(model.percentage) state=\(model.status) powerEvents=\(powerSource != nil) temperature=\(String(describing: model.snapshot.temperatureCelsius))")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [self] in
            var success = item?.button != nil && powerSource != nil
            if options.renderPreviewRequested {
                if let path = options.previewPath {
                    success = renderPreview(to: path, page: options.previewPage) && success
                } else {
                    print("UI_PREVIEW_FAILED missing output path")
                    success = false
                }
            }
            if options.interactionTest {
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

    private func runSamplingTest(_ options: HarnessOptions) {
        togglePanel()
        let initialBatteryReads = model.readCount
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) { [self] in
            let visibleReads = monitor.systemReadCount
            var success = visibleReads >= 2 && monitor.system != nil
            if let path = options.previewPath {
                success = renderPreview(to: path, page: options.previewPage) && success
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

    private func finishSmoke(success: Bool) {
        applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        print("UI_SMOKE_RESULT success=\(success)")
        fflush(stdout)
        exit(success ? 0 : 1)
    }

    /// Renders this app's own SwiftUI view only. It never captures the user's desktop.
    /// With no page and no devices the live monitor is rendered; otherwise a separate,
    /// non-sampling model seeded with the current data shows the requested tab, so the
    /// live model's sampling and device reads are never touched.
    private func renderPreview(to path: String, page: MonitorPage?, devices: DeviceSnapshot? = nil) -> Bool {
        let previewMonitor: MonitorModel
        if page != nil || devices != nil {
            previewMonitor = MonitorModel(initialDevices: devices ?? monitor.devices, initialSystem: monitor.system)
            previewMonitor.page = page ?? .devices
        } else {
            previewMonitor = monitor
        }
        let view = NSHostingView(rootView: MonitorPanel(battery: model, monitor: previewMonitor, launchAtLogin: launchAtLogin) {}
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
}
