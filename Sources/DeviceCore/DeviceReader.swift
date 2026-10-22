import Foundation

/// On-demand reader. No polling, pairing, or main-thread native calls.
/// A process-wide gate prevents hung private APIs from accumulating background work.
public final class DeviceReader: @unchecked Sendable {
    private static let nativeGate = DeviceReadGate()
    private let gate: DeviceReadGate
    private let operation: (TimeInterval, DeviceReadProgress) -> DeviceSnapshot

    public init() {
        gate = Self.nativeGate
        operation = { timeout, progress in MobileDeviceBackend.read(timeout: timeout, progress: progress) }
    }

    // Internal injection keeps timeout and unavailable-path tests independent of actual hardware.
    init(gate: DeviceReadGate, operation: @escaping (TimeInterval, DeviceReadProgress) -> DeviceSnapshot) {
        self.gate = gate
        self.operation = operation
    }

    /// Returns within the requested deadline, clamped to 0.05...15 seconds.
    /// A timed-out native call cannot be forcibly cancelled. Further reads return timedOut until it exits.
    public func read(timeout: TimeInterval = 5) async -> DeviceSnapshot {
        let duration = timeout.isFinite ? min(15, max(0.05, timeout)) : 5
        guard let progress = gate.acquire() else {
            return DeviceSnapshot(status: .timedOut, frameworkLoaded: gate.frameworkLoaded,
                                  message: "上次设备读取仍未结束，请稍后重试；若持续超时请重启应用。")
        }
        return await withCheckedContinuation { continuation in
            let completion = DeviceReadCompletion(continuation)
            let deadline = DispatchTime.now() + duration
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: deadline) {
                progress.cancel()
                completion.finish(DeviceSnapshot(status: .timedOut, frameworkLoaded: progress.frameworkLoaded,
                                                 message: "设备读取超时，请检查连接并解锁设备后重试。"))
            }
            DispatchQueue.global(qos: .utility).async { [gate, operation] in
                defer { gate.release(progress) }
                guard !progress.isCancelled else { return }
                let result = operation(duration, progress)
                completion.finish(result)
            }
        }
    }
}

final class DeviceReadProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var loaded = false
    private var cancelled = false
    private var unsafeToRepeat = false
    var isUnsafeToRepeat: Bool { lock.lock(); defer { lock.unlock() }; return unsafeToRepeat }
    func quarantine() { lock.lock(); unsafeToRepeat = true; cancelled = true; lock.unlock() }
    var frameworkLoaded: Bool { lock.lock(); defer { lock.unlock() }; return loaded }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func markLoaded() { lock.lock(); loaded = true; lock.unlock() }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}

final class DeviceReadGate: @unchecked Sendable {
    private let lock = NSLock()
    private var active: DeviceReadProgress?
    private var lastLoaded = false
    var frameworkLoaded: Bool {
        lock.lock(); defer { lock.unlock() }
        return active?.frameworkLoaded ?? lastLoaded
    }
    func acquire() -> DeviceReadProgress? {
        lock.lock(); defer { lock.unlock() }
        guard active == nil else { return nil }
        let progress = DeviceReadProgress()
        active = progress
        return progress
    }
    func release(_ progress: DeviceReadProgress) {
        lock.lock(); defer { lock.unlock() }
        if active === progress {
            lastLoaded = progress.frameworkLoaded
            if !progress.isUnsafeToRepeat { active = nil }
        }
    }
}

private final class DeviceReadCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<DeviceSnapshot, Never>?
    init(_ continuation: CheckedContinuation<DeviceSnapshot, Never>) { self.continuation = continuation }
    func finish(_ result: DeviceSnapshot) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: result)
    }
}
