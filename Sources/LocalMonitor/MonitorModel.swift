import Foundation
import Combine
import SystemCore
import DeviceCore

/// The contained non-Sendable reader is touched only by its owning serial queue.
private final class SerialSystemReader: @unchecked Sendable {
    let value = SystemReader()
}

/// No timer reads battery or connected devices. A single serial queue owns system baselines.
@MainActor
final class MonitorModel: ObservableObject {
    @Published var page: MonitorPage = .system
    @Published private(set) var system: SystemSnapshot?
    @Published private(set) var devices: DeviceSnapshot?
    @Published private(set) var isSampling = false
    @Published private(set) var isReadingDevices = false
    private let queue = DispatchQueue(label: "local.monitor.system", qos: .utility)
    private let reader = SerialSystemReader()
    private let deviceReader = DeviceReader()
    private var timer: Timer?
    private var warmUpTimer: Timer?
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
        if visible && !sleeping && page == .devices { refreshDevices() }
    }

    func pageChanged() {
        configureSampling()
        if panelVisible && page == .devices { refreshDevices() }
    }

    private func configureSampling() {
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
        timer.tolerance = interval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
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

    func refreshDevices() {
        guard panelVisible, page == .devices, !sleeping, !isReadingDevices else { return }
        isReadingDevices = true
        deviceReadCount += 1
        Task { [weak self, deviceReader] in
            let result = await deviceReader.read(timeout: 5)
            guard let self else { return }
            self.devices = result
            self.isReadingDevices = false
        }
    }

    func stop() { updateVisibility(false) }
}
