import Foundation
#if !DEVICE_STANDALONE
import XCTest
#endif
@testable import DeviceCore

final class DeviceReaderTests: XCTestCase {
    func testMissingFrameworkAndSymbolsDowngrade() {
        let missing = MobileDeviceLibrary(paths: ["/nonexistent/DeviceCore-fixture.framework/DeviceCore-fixture"])
        XCTAssertFalse(missing.loaded)
        XCTAssertFalse(missing.ready)
        let absent = MobileDeviceBackend.read(library: missing, timeout: 0.1, progress: DeviceReadProgress())
        XCTAssertEqual(absent.status, .unavailable)
        XCTAssertEqual(absent.issue, .frameworkUnavailable)
        XCTAssertFalse(absent.frameworkLoaded)
        let noSymbols = MobileDeviceLibrary(paths: ["/usr/lib/libSystem.B.dylib"], resolve: { _, _ in nil })
        XCTAssertTrue(noSymbols.loaded)
        XCTAssertFalse(noSymbols.ready)
        let result = MobileDeviceBackend.read(library: noSymbols, timeout: 0.1, progress: DeviceReadProgress())
        XCTAssertEqual(result.status, .unavailable)
        XCTAssertEqual(result.issue, .frameworkUnavailable)
        XCTAssertTrue(result.frameworkLoaded)
    }

    func testDeadlineDoesNotAccumulateNativeWork() async {
        let gate = DeviceReadGate()
        let release = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        let counter = LockedCounter()
        let reader = DeviceReader(gate: gate) { _, progress in
            counter.increment()
            progress.markLoaded()
            _ = release.wait(timeout: .now() + 2)
            defer { finished.signal() }
            return DeviceSnapshot(status: .noDevice, frameworkLoaded: true, message: "fixture")
        }
        let start = ProcessInfo.processInfo.systemUptime
        let first = await reader.read(timeout: 0.05)
        XCTAssertEqual(counter.value, 1)
        XCTAssertEqual(first.status, .timedOut)
        XCTAssertNil(first.issue)
        XCTAssertTrue(first.frameworkLoaded)
        XCTAssertTrue(ProcessInfo.processInfo.systemUptime - start < 1)
        let second = await reader.read(timeout: 0.05)
        XCTAssertEqual(second.status, .timedOut)
        XCTAssertEqual(second.issue, .readInProgress)
        XCTAssertEqual(counter.value, 1)
        release.signal()
        let didFinish: DispatchTimeoutResult = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: finished.wait(timeout: .now() + 1))
            }
        }
        XCTAssertEqual(didFinish, .success)
    }

    func testSuccessfulReadAndQuarantinedGate() async {
        let reader = DeviceReader(gate: DeviceReadGate()) { _, _ in
            DeviceSnapshot(status: .noDevice, frameworkLoaded: true, message: "fixture no device")
        }
        let value = await reader.read(timeout: 0.2)
        XCTAssertEqual(value.status, .noDevice)
        XCTAssertNil(value.issue)
        XCTAssertTrue(value.devices.isEmpty)
        let gate = DeviceReadGate()
        let progress = gate.acquire()!
        progress.quarantine()
        gate.release(progress)
        XCTAssertNil(gate.acquire())
    }

    /// A busy gate and a quarantined gate are told apart atomically by attempt().
    func testGateAttemptDistinguishesBusyAndQuarantined() {
        let gate = DeviceReadGate()
        var acquired: DeviceReadProgress?
        if case .acquired(let progress) = gate.attempt() { acquired = progress }
        XCTAssertNotNil(acquired)
        var busy = false
        if case .busy = gate.attempt() { busy = true }
        XCTAssertTrue(busy)
        if let acquired {
            // A normal release frees the gate again.
            gate.release(acquired)
            var reacquired: DeviceReadProgress?
            if case .acquired(let progress) = gate.attempt() { reacquired = progress }
            XCTAssertNotNil(reacquired)
            if let reacquired {
                // Quarantine is visible both while the read is still active and after its release.
                reacquired.quarantine()
                var quarantinedWhileActive = false
                if case .quarantined = gate.attempt() { quarantinedWhileActive = true }
                XCTAssertTrue(quarantinedWhileActive)
                gate.release(reacquired)
                var quarantinedAfterRelease = false
                if case .quarantined = gate.attempt() { quarantinedAfterRelease = true }
                XCTAssertTrue(quarantinedAfterRelease)
            }
        }
    }

    /// The reader maps a refused gate to the truthful status and issue code without running work.
    func testGateRefusalReasonsInSnapshots() async {
        let counter = LockedCounter()
        let busyGate = DeviceReadGate()
        let held = busyGate.acquire()
        XCTAssertNotNil(held)
        let busyReader = DeviceReader(gate: busyGate) { _, _ in
            counter.increment()
            return DeviceSnapshot(status: .noDevice, message: "fixture")
        }
        let busy = await busyReader.read(timeout: 0.2)
        XCTAssertEqual(busy.status, .timedOut)
        XCTAssertEqual(busy.issue, .readInProgress)

        let quarantinedGate = DeviceReadGate()
        if let progress = quarantinedGate.acquire() {
            progress.quarantine()
            quarantinedGate.release(progress)
        }
        let quarantinedReader = DeviceReader(gate: quarantinedGate) { _, _ in
            counter.increment()
            return DeviceSnapshot(status: .noDevice, message: "fixture")
        }
        let quarantined = await quarantinedReader.read(timeout: 0.2)
        XCTAssertEqual(quarantined.status, .unavailable)
        XCTAssertEqual(quarantined.issue, .notificationCleanupFailed)
        XCTAssertEqual(counter.value, 0)
        if let held { busyGate.release(held) }
    }

    /// No device seen: wait until the hard end, exactly as before the early-stop change.
    func testScanPolicyWithoutDeviceWaitsUntilHardEnd() {
        XCTAssertTrue(DeviceScanPolicy.shouldKeepWaiting(now: 10.0, scanStart: 10.0, hardEnd: 11.5,
                                                         lastEventAt: nil, deviceCount: 0))
        XCTAssertTrue(DeviceScanPolicy.shouldKeepWaiting(now: 11.49, scanStart: 10.0, hardEnd: 11.5,
                                                         lastEventAt: nil, deviceCount: 0))
        // A device that attached and detached again leaves no device: keep waiting.
        XCTAssertTrue(DeviceScanPolicy.shouldKeepWaiting(now: 11.0, scanStart: 10.0, hardEnd: 11.5,
                                                         lastEventAt: 10.1, deviceCount: 0))
        XCTAssertFalse(DeviceScanPolicy.shouldKeepWaiting(now: 11.5, scanStart: 10.0, hardEnd: 11.5,
                                                          lastEventAt: nil, deviceCount: 0))
        XCTAssertFalse(DeviceScanPolicy.shouldKeepWaiting(now: 12.0, scanStart: 10.0, hardEnd: 11.5,
                                                          lastEventAt: nil, deviceCount: 0))
    }

    /// With a device seen, stop once the list has been quiet; the hard end still always wins.
    func testScanPolicyStopsAfterQuietPeriodWithDevice() {
        let quiet = DeviceScanPolicy.quietPeriod
        XCTAssertTrue(quiet >= 0.25 && quiet <= 0.3)
        XCTAssertTrue(DeviceScanPolicy.shouldKeepWaiting(now: 10.1, scanStart: 10.0, hardEnd: 11.5,
                                                         lastEventAt: 10.01, deviceCount: 1))
        XCTAssertFalse(DeviceScanPolicy.shouldKeepWaiting(now: 10.01 + quiet + 0.01, scanStart: 10.0, hardEnd: 11.5,
                                                          lastEventAt: 10.01, deviceCount: 1))
        // A later event (second device) restarts the quiet period.
        XCTAssertTrue(DeviceScanPolicy.shouldKeepWaiting(now: 10.5, scanStart: 10.0, hardEnd: 11.5,
                                                         lastEventAt: 10.4, deviceCount: 2))
        // An event delivered during subscribe (before scanStart) is measured from scanStart.
        XCTAssertTrue(DeviceScanPolicy.shouldKeepWaiting(now: 10.1, scanStart: 10.0, hardEnd: 11.5,
                                                         lastEventAt: 9.0, deviceCount: 1))
        XCTAssertFalse(DeviceScanPolicy.shouldKeepWaiting(now: 10.0 + quiet + 0.01, scanStart: 10.0, hardEnd: 11.5,
                                                          lastEventAt: 9.0, deviceCount: 1))
        // Hard end wins even mid-burst.
        XCTAssertFalse(DeviceScanPolicy.shouldKeepWaiting(now: 11.5, scanStart: 10.0, hardEnd: 11.5,
                                                          lastEventAt: 11.49, deviceCount: 1))
    }

    /// USB only: skip exactly interface type 2 (Wi-Fi); anything else, or no symbol, is read as before.
    func testTransportPolicySkipsOnlyWiFi() {
        XCTAssertTrue(DeviceTransportPolicy.shouldSkip(interfaceType: 2))
        XCTAssertFalse(DeviceTransportPolicy.shouldSkip(interfaceType: 1))
        XCTAssertFalse(DeviceTransportPolicy.shouldSkip(interfaceType: nil))
        for other: Int32 in [0, 3, -1, Int32.max, Int32.min] {
            XCTAssertFalse(DeviceTransportPolicy.shouldSkip(interfaceType: other))
        }
    }

    /// AMDeviceGetInterfaceType is optional: its absence never affects readiness.
    /// The fake addresses below are only stored, never called.
    func testInterfaceTypeSymbolIsOptional() {
        guard let fake = UnsafeMutableRawPointer(bitPattern: 0x1000) else {
            XCTAssertTrue(false)
            return
        }
        let withoutTransport = MobileDeviceLibrary(paths: ["/usr/lib/libSystem.B.dylib"], resolve: { _, name in
            name == "AMDeviceGetInterfaceType" ? nil : fake
        })
        XCTAssertTrue(withoutTransport.ready)
        XCTAssertTrue(withoutTransport.interfaceType == nil)
        let withTransport = MobileDeviceLibrary(paths: ["/usr/lib/libSystem.B.dylib"], resolve: { _, _ in fake })
        XCTAssertTrue(withTransport.ready)
        XCTAssertTrue(withTransport.interfaceType != nil)
        let onlyTransport = MobileDeviceLibrary(paths: ["/usr/lib/libSystem.B.dylib"], resolve: { _, name in
            name == "AMDeviceGetInterfaceType" ? fake : nil
        })
        XCTAssertFalse(onlyTransport.ready)
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    func increment() { lock.lock(); count += 1; lock.unlock() }
}
