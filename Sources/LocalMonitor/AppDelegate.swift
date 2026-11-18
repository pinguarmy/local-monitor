import AppKit
import SwiftUI
import Combine
import BatteryCore
import IOKit.ps

/// Resolves the first SF Symbol that exists on this system from a fallback list.
/// `NSImage(systemSymbolName:)` returns nil for names the running macOS does not know.
enum StatusItemGlyph {
    static func firstAvailable(_ names: [String], accessibilityDescription: String? = nil) -> (name: String, image: NSImage)? {
        for name in names {
            if let image = NSImage(systemSymbolName: name, accessibilityDescription: accessibilityDescription) {
                return (name: name, image: image)
            }
        }
        return nil
    }
}

/// Menu bar item, popover and system event wiring. Launch-argument test modes live in
/// AppDelegate+Harness.swift.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let model = BatteryModel()
    let monitor = MonitorModel()
    let launchAtLogin = LaunchAtLogin()
    private(set) var item: NSStatusItem?
    let popover = NSPopover()
    private var wakeObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    private var powerModeObserver: NSObjectProtocol?
    private var changeObserver: AnyCancellable?
    private(set) var powerSource: CFRunLoopSource?
    private var pendingPowerRefresh: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.item = item
        if let button = item.button {
            button.target = self
            button.action = #selector(togglePanel)
            button.sendAction(on: [.leftMouseUp])
            button.setAccessibilityLabel(L10n.appName)
        }
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: MonitorPanel(
            battery: model, monitor: monitor, launchAtLogin: launchAtLogin) { NSApp.terminate(nil) })
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
        startHarnessIfRequested()
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

    private func updateStatus() {
        guard let button = item?.button else { return }
        let snapshot = model.snapshot
        let isAbsent = snapshot.availability == .absent
        let description = isAbsent ? L10n.appName : BatteryPresentation.status(snapshot)
        let glyph = StatusItemGlyph.firstAvailable(BatteryPresentation.statusItemSymbols(snapshot),
                                                   accessibilityDescription: description)?.image
        button.title = BatteryPresentation.statusItemTitle(snapshot)
        button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        if !isAbsent, snapshot.isCharging == true, let glyph,
           let bolt = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: L10n.chargingIndicator) {
            // SF Symbols provides only battery.100.bolt, not per-level bolt variants.
            // Compose the actual battery level with a separate charging indicator.
            let image = NSImage(size: NSSize(width: 32, height: 14), flipped: false) { _ in
                glyph.draw(in: NSRect(x: 0, y: 1, width: 23, height: 12))
                bolt.draw(in: NSRect(x: 25, y: 1, width: 7, height: 12))
                return true
            }
            image.isTemplate = true
            button.image = image
        } else {
            button.image = glyph
        }
        if isAbsent {
            // No battery: a neutral glyph alone. Only if no glyph resolves, fall back to the app name.
            if glyph == nil { button.title = L10n.appName }
            button.imagePosition = glyph == nil ? .noImage : .imageOnly
        } else {
            button.imagePosition = .imageLeading
        }
        button.toolTip = BatteryPresentation.statusItemToolTip(snapshot)
        button.setAccessibilityValue(BatteryPresentation.statusItemAccessibilityValue(snapshot))
    }

    @objc func togglePanel() {
        guard let button = item?.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else {
            model.refresh()
            launchAtLogin.reload()
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
