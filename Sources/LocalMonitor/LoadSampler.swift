import Foundation
import Combine
import SystemCore

/// The contained non-Sendable reader is touched only by its owning serial queue.
private final class SerialLoadReader: @unchecked Sendable {
    let value = SystemLoadReader()
}

/// Background CPU / memory sampling for the menu bar title. Runs only while the selected
/// metric needs it (`SamplingPolicy.menuBarInterval`), pauses across sleep, and never runs two
/// reads at once. Battery and icon-only modes leave it idle.
@MainActor
final class LoadSampler: ObservableObject {
    /// Nil until the first read of the current sampling session, and whenever sampling is off.
    @Published private(set) var sample: SystemLoadSample?
    private let queue = DispatchQueue(label: "local.monitor.menubar-load", qos: .utility)
    private let reader = SerialLoadReader()
    private var timer: Timer?
    private var warmUpTimer: Timer?
    private var metric: MenuBarMetric = .iconOnly
    private var sleeping = false
    private var stopped = false
    /// The CPU baseline must be reset before the next session's first read: set initially and
    /// whenever sampling is switched off by the metric, so a stale baseline never averages
    /// over the time the menu bar showed something else. Sleep and Low Power Mode keep it.
    private var needsBaselineReset = true
    private var inFlight = false
    private var readPending = false
    private var generation = 0
    private(set) var readCount = 0
    private(set) var interval: TimeInterval?

    var isRunning: Bool { timer != nil }

    func update(metric: MenuBarMetric) {
        guard metric != self.metric else { return }
        self.metric = metric
        if !metric.needsLoadSampling {
            sample = nil
            needsBaselineReset = true
        }
        reconfigure()
    }

    func setSleeping(_ sleeping: Bool) {
        guard sleeping != self.sleeping else { return }
        self.sleeping = sleeping
        reconfigure()
    }

    /// Low Power Mode changed: the interval may have changed.
    func powerStateChanged() { reconfigure() }

    /// Final stop at termination; nothing restarts afterwards.
    func stop() {
        stopped = true
        reconfigure()
    }

    private func reconfigure() {
        timer?.invalidate()
        timer = nil
        warmUpTimer?.invalidate()
        warmUpTimer = nil
        generation += 1
        let interval = stopped ? nil : SamplingPolicy.menuBarInterval(
            metric: metric, isSleeping: sleeping, lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
        self.interval = interval
        guard let interval else {
            readPending = false
            return
        }
        let requestGeneration = generation
        if needsBaselineReset {
            needsBaselineReset = false
            // Enqueued before the next read on the same serial queue.
            queue.async { [reader] in reader.value.resetBaseline() }
            // A CPU percentage needs two reads; take the second one early.
            if let delay = SamplingPolicy.warmUpDelay(interval: interval) {
                let warmUp = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self, self.generation == requestGeneration else { return }
                        self.requestRead()
                    }
                }
                RunLoop.main.add(warmUp, forMode: .common)
                warmUpTimer = warmUp
            }
        }
        requestRead()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.timerTick() }
        }
        timer.tolerance = SamplingPolicy.tolerance(interval: interval)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Regular ticks skip while a read is still running instead of queueing a back-to-back read.
    private func timerTick() {
        guard !inFlight else { return }
        requestRead()
    }

    /// A (re)start or warm-up request during an in-flight read is issued when that read returns.
    private func requestRead() {
        guard interval != nil else { return }
        guard !inFlight else {
            readPending = true
            return
        }
        readPending = false
        inFlight = true
        let requestGeneration = generation
        queue.async { [reader, weak self] in
            let sample = reader.value.read()
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.inFlight = false
                self.readCount += 1
                // A result from before a restart or metric change is discarded.
                if self.generation == requestGeneration, self.interval != nil {
                    self.sample = sample
                }
                if self.readPending {
                    self.readPending = false
                    self.requestRead()
                }
            }
        }
    }
}
