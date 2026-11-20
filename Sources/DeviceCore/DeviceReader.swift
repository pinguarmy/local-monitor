import Foundation

/// On-demand reader for USB-connected, already-trusted iPhone/iPad devices.
/// No polling, pairing, or main-thread native calls; no persistent identifiers are read.
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
    /// A timed-out native call cannot be forcibly cancelled. Further reads return timedOut
    /// (issue `readInProgress`) until it exits. After a failed notification unsubscribe the gate
    /// is quarantined and every later read returns unavailable (issue `notificationCleanupFailed`).
    public func read(timeout: TimeInterval = 5) async -> DeviceSnapshot {
        let duration = timeout.isFinite ? min(15, max(0.05, timeout)) : 5
        let progress: DeviceReadProgress
        switch gate.attempt() {
        case .acquired(let acquired):
            progress = acquired
        case .busy:
            return DeviceSnapshot(status: .timedOut, frameworkLoaded: gate.frameworkLoaded,
                                  message: DeviceMessage.readInProgress, issue: .readInProgress)
        case .quarantined:
            // The gate is held forever after a failed unsubscribe; waiting will never help.
            return DeviceSnapshot(status: .unavailable, frameworkLoaded: gate.frameworkLoaded,
                                  message: DeviceMessage.notificationCleanupFailed, issue: .notificationCleanupFailed)
        }
        return await withCheckedContinuation { continuation in
            let completion = DeviceReadCompletion(continuation)
            let deadline = DispatchTime.now() + duration
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: deadline) {
                progress.cancel()
                completion.finish(DeviceSnapshot(status: .timedOut, frameworkLoaded: progress.frameworkLoaded,
                                                 message: DeviceMessage.timedOut))
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

enum DeviceReadGateAttempt {
    case acquired(DeviceReadProgress)
    case busy
    case quarantined
}

final class DeviceReadGate: @unchecked Sendable {
    private let lock = NSLock()
    private var active: DeviceReadProgress?
    private var lastLoaded = false
    var frameworkLoaded: Bool {
        lock.lock(); defer { lock.unlock() }
        return active?.frameworkLoaded ?? lastLoaded
    }
    /// Atomically takes the gate, or reports why it is held: a read still running (`busy`), or
    /// a read that quarantined the gate after a failed unsubscribe (`quarantined`, permanent).
    /// Lock order is always gate lock, then progress lock; progress never takes the gate lock.
    func attempt() -> DeviceReadGateAttempt {
        lock.lock(); defer { lock.unlock() }
        if let active {
            return active.isUnsafeToRepeat ? .quarantined : .busy
        }
        let progress = DeviceReadProgress()
        active = progress
        return .acquired(progress)
    }
    func acquire() -> DeviceReadProgress? {
        if case .acquired(let progress) = attempt() { return progress }
        return nil
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

/// Fixed English snapshot messages shared by the reader and the native backend.
/// They never contain device data or raw framework errors.
enum DeviceMessage {
    static let frameworkUnavailable = "The MobileDevice framework or a required function is not available on this Mac."
    static let subscriptionFailed = "Could not subscribe to local device connection notifications."
    static let notificationCleanupFailed = "Could not stop device notifications. Restart the app before reading devices again."
    static let readInProgress = "A previous device read has not finished yet. Try again shortly; if it keeps timing out, restart the app."
    static let timedOut = "Device read timed out. Check the connection, unlock the device and try again."
    static let timedOutDuringRead = "Device read timed out. Check the connection and try again."
    static let communicationTimedOut = "Device communication timed out. Check the connection and try again."
    static let noDevice = "No locally connected iPhone or iPad found. Connect it with a USB cable, unlock it, trust this Mac, then refresh manually."
    static let noUSBDevice = "No USB-connected iPhone or iPad found. Devices visible only over Wi-Fi are not read."
    static let noReadableDevice = "No readable iPhone or iPad found."
    static let available = "Read from locally trusted devices. Only read-only metrics the device reports are shown."
    static let partiallyAvailable = "Some devices were read; others could not be read. Check that they are unlocked, trusted and connected."
    static let requiresUnlockAndTrust = "The device must be unlocked and trust this Mac. Complete trust manually in Finder and on the device, then refresh. This app never pairs automatically."
    static let deviceUnreadable = "A device was found but cannot be read right now. Check the connection and any device restrictions, then try again."
}
