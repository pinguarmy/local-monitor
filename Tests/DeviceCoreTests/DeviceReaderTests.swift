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
        XCTAssertFalse(absent.frameworkLoaded)
        let noSymbols = MobileDeviceLibrary(paths: ["/usr/lib/libSystem.B.dylib"], resolve: { _, _ in nil })
        XCTAssertTrue(noSymbols.loaded)
        XCTAssertFalse(noSymbols.ready)
        let result = MobileDeviceBackend.read(library: noSymbols, timeout: 0.1, progress: DeviceReadProgress())
        XCTAssertEqual(result.status, .unavailable)
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
        XCTAssertTrue(first.frameworkLoaded)
        XCTAssertTrue(ProcessInfo.processInfo.systemUptime - start < 1)
        let second = await reader.read(timeout: 0.05)
        XCTAssertEqual(second.status, .timedOut)
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
        XCTAssertTrue(value.devices.isEmpty)
        let gate = DeviceReadGate()
        let progress = gate.acquire()!
        progress.quarantine()
        gate.release(progress)
        XCTAssertNil(gate.acquire())
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    func increment() { lock.lock(); count += 1; lock.unlock() }
}
