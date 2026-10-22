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
    private var panelVisible = false
    private var sleeping = false
    private var inFlight = false
    private var generation = 0
    private(set) var systemReadCount = 0
    private(set) var deviceReadCount = 0

    init(initialDevices: DeviceSnapshot? = nil) { self.devices = initialDevices }

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
        generation += 1
        let interval = SamplingPolicy.systemInterval(panelVisible: panelVisible, page: page,
            isSleeping: sleeping, lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
        isSampling = interval != nil
        guard let interval else { return }
        queue.async { [reader] in reader.value.resetBaselines() }
        refreshSystem()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshSystem() }
        }
        timer.tolerance = interval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func refreshSystem() {
        guard panelVisible, page == .system, !sleeping, !inFlight else { return }
        inFlight = true
        let requestGeneration = generation
        queue.async { [reader, weak self] in
            let sample = reader.value.read()
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.inFlight = false
                self.systemReadCount += 1
                guard self.generation == requestGeneration, self.isSampling else { return }
                self.system = sample
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
