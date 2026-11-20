import Foundation
import Combine
import SystemCore
import BatteryCore
import DeviceCore

/// The contained non-Sendable reader is touched only by its owning serial queue.
private final class SerialSystemReader: @unchecked Sendable {
    let value = SystemReader()
}

/// Panel timers, each running only while the panel is visible on its tab and the Mac is awake
/// (intervals in `SamplingPolicy`): system sampling on the System tab, a battery refresh on the
/// Battery tab and a silent device re-read on the Devices tab. A single serial queue owns
/// system baselines.
@MainActor
final class MonitorModel: ObservableObject {
    @Published var page: MonitorPage = .system
    @Published private(set) var system: SystemSnapshot?
    @Published private(set) var devices: DeviceSnapshot?
    @Published private(set) var isSampling = false
    /// Progress for the current device read ("Reading…", Refresh disabled). Only manual refresh
    /// and the very first read show it; tab-open and timer reads are silent.
    @Published private(set) var showsDeviceProgress = false
    /// At most one device read runs at a time, shown or silent.
    private(set) var isReadingDevices = false
    /// Refreshed by the battery timer; set by AppDelegate. Nil in previews, so they never read.
    weak var battery: BatteryModel?
    private let queue = DispatchQueue(label: "local.monitor.system", qos: .utility)
    private let reader = SerialSystemReader()
    private let deviceReader = DeviceReader()
    private var timer: Timer?
    private var warmUpTimer: Timer?
    private var batteryTimer: Timer?
    private var deviceTimer: Timer?
    private var panelVisible = false
    private var sleeping = false
    /// At most one system read runs at a time.
    private var inFlight = false
    /// A refresh was requested while a read was in flight; issue it as soon as that read returns.
    private var refreshPending = false
    private var generation = 0
    private(set) var systemReadCount = 0
    private(set) var deviceReadCount = 0

    /// `initialSystem` and `initialDevices` seed preview renders without starting any reads.
    init(initialDevices: DeviceSnapshot? = nil, initialSystem: SystemSnapshot? = nil) {
        self.devices = initialDevices
        self.system = initialSystem
    }

    func updateVisibility(_ visible: Bool, sleeping: Bool = false) {
        panelVisible = visible
        self.sleeping = sleeping
        configureSampling()
        if visible && !sleeping && page == .devices { readDevices(showProgress: false) }
    }

    func pageChanged() {
        configureSampling()
        if panelVisible && page == .devices { readDevices(showProgress: false) }
    }

    var isBatteryTimerRunning: Bool { batteryTimer != nil }
    var isDeviceTimerRunning: Bool { deviceTimer != nil }

    private func configureSampling() {
        configureSystemSampling()
        configureBatteryTimer()
        configureDeviceTimer()
    }

    private func configureSystemSampling() {
        timer?.invalidate()
        timer = nil
        warmUpTimer?.invalidate()
        warmUpTimer = nil
        generation += 1
        let interval = SamplingPolicy.systemInterval(panelVisible: panelVisible, page: page,
            isSleeping: sleeping, lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
        isSampling = interval != nil
        guard let interval else {
            refreshPending = false
            return
        }
        // Enqueued before the next read. A read already in flight finishes first on the same
        // serial queue; its result carries the old generation and is discarded.
        queue.async { [reader] in reader.value.resetBaselines() }
        refreshSystem()
        let requestGeneration = generation
        if let delay = SamplingPolicy.warmUpDelay(interval: interval) {
            let warmUp = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == requestGeneration else { return }
                    self.refreshSystem()
                }
            }
            RunLoop.main.add(warmUp, forMode: .common)
            warmUpTimer = warmUp
        }
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.timerTick() }
        }
        timer.tolerance = SamplingPolicy.tolerance(interval: interval)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Battery reads stay synchronous on the main actor (about a millisecond each).
    private func configureBatteryTimer() {
        batteryTimer?.invalidate()
        batteryTimer = nil
        let hasBattery = battery.map { $0.snapshot.availability != .absent } ?? false
        guard let interval = SamplingPolicy.batteryInterval(panelVisible: panelVisible, page: page, isSleeping: sleeping,
            lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled, hasBattery: hasBattery) else { return }
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.battery?.refresh() }
        }
        timer.tolerance = SamplingPolicy.tolerance(interval: interval)
        RunLoop.main.add(timer, forMode: .common)
        batteryTimer = timer
    }

    /// Re-armed after every device read, so the next silent read starts a full interval after
    /// the previous one finished and stops once a read reports a cleanup failure.
    private func configureDeviceTimer() {
        deviceTimer?.invalidate()
        deviceTimer = nil
        guard let interval = SamplingPolicy.deviceInterval(panelVisible: panelVisible, page: page, isSleeping: sleeping,
            lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled, lastIssue: devices?.issue) else { return }
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.readDevices(showProgress: false) }
        }
        timer.tolerance = SamplingPolicy.tolerance(interval: interval)
        RunLoop.main.add(timer, forMode: .common)
        deviceTimer = timer
    }

    /// Regular ticks skip while a read is still running instead of queueing a back-to-back read.
    private func timerTick() {
        guard !inFlight else { return }
        refreshSystem()
    }

    /// Manual refresh, sampling (re)start and the warm-up sample. If a read is in flight, the
    /// request is remembered and issued when that read returns, so a restart always produces a
    /// prompt sample of the new generation without ever running two reads concurrently.
    func refreshSystem() {
        guard panelVisible, page == .system, !sleeping else { return }
        guard !inFlight else {
            refreshPending = true
            return
        }
        refreshPending = false
        inFlight = true
        let requestGeneration = generation
        queue.async { [reader, weak self] in
            let sample = reader.value.read()
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.inFlight = false
                self.systemReadCount += 1
                if self.generation == requestGeneration, self.isSampling {
                    self.system = sample
                }
                if self.refreshPending {
                    self.refreshPending = false
                    self.refreshSystem()
                }
            }
        }
    }

    /// Manual Refresh: always shows progress.
    func refreshDevices() { readDevices(showProgress: true) }

    /// Never overlaps reads. A shown request during a silent read makes that read show progress
    /// instead of starting another. The very first read (no snapshot yet) always shows progress.
    private func readDevices(showProgress requested: Bool) {
        guard panelVisible, page == .devices, !sleeping else { return }
        let showProgress = requested || devices == nil
        guard !isReadingDevices else {
            if showProgress { showsDeviceProgress = true }
            return
        }
        isReadingDevices = true
        showsDeviceProgress = showProgress
        deviceReadCount += 1
        Task { [weak self, deviceReader] in
            let result = await deviceReader.read(timeout: 5)
            guard let self else { return }
            self.devices = result
            self.isReadingDevices = false
            self.showsDeviceProgress = false
            self.configureDeviceTimer()
        }
    }

    func stop() { updateVisibility(false) }
}
