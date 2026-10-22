import Foundation
import Darwin
@testable import SystemCore
#if !SYSTEM_STANDALONE
import XCTest
#endif

final class SystemCoreTests: XCTestCase {
    func testCPUNeedsTwoSamplesAndCountsNiceAsBusy() {
        let first = CPUTicks(user: 10, system: 20, idle: 30, nice: 40)
        let second = CPUTicks(user: 20, system: 30, idle: 100, nice: 50)
        XCTAssertNil(first.utilization(since: nil))
        XCTAssertEqual(second.utilization(since: first)!, 30, accuracy: 0.0001)
        XCTAssertNil(first.utilization(since: first))
    }

    func testCPUCounterResetAndWrapCannotUnderflow() {
        let previous = CPUTicks(user: UInt32.max, system: 100, idle: 100, nice: 0)
        let wrapped = CPUTicks(user: 4, system: 110, idle: 110, nice: 0)
        XCTAssertNil(wrapped.utilization(since: previous))
        let idle = CPUTicks(user: 4, system: 110, idle: 210, nice: 0)
        XCTAssertEqual(idle.utilization(since: wrapped)!, 0, accuracy: 0)
        let busy = CPUTicks(user: 104, system: 110, idle: 210, nice: 0)
        XCTAssertEqual(busy.utilization(since: idle)!, 100, accuracy: 0)
    }

    func testMemoryFormulaDoesNotDoubleCountFileCacheOrSpeculativePages() {
        let memory = SystemMetrics.memory(totalBytes: 1_000_000, pageSize: 1000, internalPages: 200, purgeablePages: 20, wiredPages: 100, compressorPages: 50, swapUsedBytes: 0, pressure: .warning)
        XCTAssertEqual(memory.usedBytes, 330_000)
        XCTAssertEqual(memory.availableBytes, 670_000)
        XCTAssertEqual(memory.compressedBytes, 50_000)
        XCTAssertEqual(memory.swapUsedBytes, 0)
        XCTAssertEqual(memory.pressure, .warning)
    }

    func testMemoryCountersAreClampedWithoutOverflow() {
        let memory = SystemMetrics.memory(totalBytes: 100, pageSize: UInt64.max, internalPages: 0, purgeablePages: 10, wiredPages: UInt64.max, compressorPages: UInt64.max, swapUsedBytes: nil, pressure: .unknown)
        XCTAssertEqual(memory.usedBytes, 100)
        XCTAssertEqual(memory.availableBytes, 0)
        XCTAssertEqual(memory.compressedBytes, 100)
        XCTAssertNil(memory.swapUsedBytes)
        let empty = SystemMetrics.memory(totalBytes: 100, pageSize: 1, internalPages: 10, purgeablePages: 20, wiredPages: 0, compressorPages: 0, swapUsedBytes: nil, pressure: .normal)
        XCTAssertEqual(empty.usedBytes, 0)
        XCTAssertEqual(empty.availableBytes, 100)
    }

    func testPressureUsesKernelLevelsNotUsedPercentage() {
        XCTAssertEqual(SystemMetrics.pressure(raw: 1), .normal)
        XCTAssertEqual(SystemMetrics.pressure(raw: 2), .warning)
        XCTAssertEqual(SystemMetrics.pressure(raw: 4), .critical)
        XCTAssertEqual(SystemMetrics.pressure(raw: 3), .unknown)
        XCTAssertEqual(SystemMetrics.pressure(raw: nil), .unknown)
    }

    func testNetworkNeedsBaselineAndUsesInterval() {
        let first = [InterfaceCounters(index: 3, received: 1000, sent: 500)]
        let second = [InterfaceCounters(index: 3, received: 3000, sent: 1000)]
        let initial = SystemMetrics.network(interfaces: first, uptime: 10, previous: nil)
        XCTAssertNil(initial.downloadBytesPerSecond)
        XCTAssertNil(initial.uploadBytesPerSecond)
        XCTAssertNil(initial.intervalSeconds)
        let sample = SystemMetrics.network(interfaces: second, uptime: 12, previous: NetworkBaseline(uptime: 10, interfaces: first))
        XCTAssertEqual(sample.downloadBytesPerSecond!, 1000, accuracy: 0)
        XCTAssertEqual(sample.uploadBytesPerSecond!, 250, accuracy: 0)
        XCTAssertEqual(sample.intervalSeconds!, 2, accuracy: 0)
    }

    func testNetworkRejectsResetEvenWhenAggregateIncreases() {
        let first = [InterfaceCounters(index: 1, received: 100, sent: 100), InterfaceCounters(index: 2, received: 100, sent: 100)]
        let second = [InterfaceCounters(index: 1, received: 10, sent: 10), InterfaceCounters(index: 2, received: 1000, sent: 1000)]
        let reset = SystemMetrics.network(interfaces: second, uptime: 12, previous: NetworkBaseline(uptime: 10, interfaces: first))
        XCTAssertNil(reset.downloadBytesPerSecond)
        XCTAssertNil(reset.uploadBytesPerSecond)
        XCTAssertNil(reset.intervalSeconds)
        XCTAssertEqual(reset.receivedBytes, 1010)
    }

    func testNetworkInterfaceChangesAndInvalidTimeRebaseline() {
        let first = [InterfaceCounters(index: 1, received: 100, sent: 100)]
        let old = NetworkBaseline(uptime: 10, interfaces: first)
        for current in [[], [InterfaceCounters(index: 2, received: 200, sent: 200)]] {
            XCTAssertNil(SystemMetrics.network(interfaces: current, uptime: 12, previous: old).intervalSeconds)
        }
        for now in [10, 9, Double.nan, Double.infinity] {
            XCTAssertNil(SystemMetrics.network(interfaces: first, uptime: now, previous: old).intervalSeconds)
        }
    }

    func testNetworkDeduplicatesAndRetains64BitCounters() {
        let big = UInt64(UInt32.max) + 1_000
        let first = InterfaceCounters(index: 2, received: big, sent: big)
        let sample = SystemMetrics.network(interfaces: [first, first], uptime: 20, previous: nil)
        XCTAssertEqual(sample.receivedBytes, big)
        XCTAssertEqual(sample.sentBytes, big)
        let second = InterfaceCounters(index: 2, received: big + 100, sent: big + 200)
        let rate = SystemMetrics.network(interfaces: [second], uptime: 22, previous: NetworkBaseline(uptime: 20, interfaces: [first]))
        XCTAssertEqual(rate.downloadBytesPerSecond!, 50, accuracy: 0)
        XCTAssertEqual(rate.uploadBytesPerSecond!, 100, accuracy: 0)
    }

    func testNetworkFilterExcludesLoopbackAndOverlayDuplicates() {
        XCTAssertTrue(SystemMetrics.isEligibleInterface(name: "en0", flags: UInt32(IFF_UP), family: UInt8(AF_LINK)))
        XCTAssertTrue(SystemMetrics.isEligibleInterface(name: "en12", flags: UInt32(IFF_UP), family: UInt8(AF_LINK)))
        for name in ["lo0", "utun0", "bridge0", "awdl0", "llw0", "en", "enx", "pdp_ip0"] {
            XCTAssertFalse(SystemMetrics.isEligibleInterface(name: name, flags: UInt32(IFF_UP), family: UInt8(AF_LINK)))
        }
        XCTAssertFalse(SystemMetrics.isEligibleInterface(name: "en0", flags: 0, family: UInt8(AF_LINK)))
        XCTAssertFalse(SystemMetrics.isEligibleInterface(name: "en0", flags: UInt32(IFF_UP | IFF_LOOPBACK), family: UInt8(AF_LINK)))
        XCTAssertFalse(SystemMetrics.isEligibleInterface(name: "en0", flags: UInt32(IFF_UP), family: UInt8(AF_INET)))
    }

    func testGPUAcceptsOnlyWhitelistedFinitePercentages() {
        XCTAssertEqual(SystemMetrics.gpuUtilization(statistics: ["Device Utilization %": 0]), 0)
        XCTAssertEqual(SystemMetrics.gpuUtilization(statistics: ["GPU Activity(%)": 100]), 100)
        XCTAssertEqual(SystemMetrics.gpuUtilization(statistics: ["Device Utilization %": 42.5]), 42.5)
        XCTAssertNil(SystemMetrics.gpuUtilization(statistics: ["GPU Busy": 90]))
        XCTAssertNil(SystemMetrics.gpuUtilization(statistics: ["Device Utilization %": true]))
        XCTAssertNil(SystemMetrics.gpuUtilization(statistics: ["Device Utilization %": "50"]))
        for invalid in [-1, 101, Double.nan, Double.infinity] {
            XCTAssertNil(SystemMetrics.gpuUtilization(statistics: ["Device Utilization %": invalid]))
        }
        XCTAssertNil(SystemMetrics.gpuUtilization(statistics: [:]))
    }

    func testSaturatingArithmeticNeverTraps() {
        XCTAssertEqual(SystemMetrics.saturatingAdd(UInt64.max, 1), UInt64.max)
        XCTAssertEqual(SystemMetrics.saturatingMultiply(UInt64.max, 2), UInt64.max)
        XCTAssertEqual(SystemMetrics.saturatingMultiply(UInt64.max, 0), 0)
    }

    func testSnapshotRoundTripKeepsUnknownsAndNoIdentifiers() throws {
        let snapshot = SystemSnapshot(timestamp: Date(timeIntervalSince1970: 0), cpu: CPUStats(logicalCoreCount: 10, physicalCoreCount: 10, usagePercent: nil, loadAverage1: 5, loadAverage5: 4, loadAverage15: 3), gpu: GPUStats(name: "Apple GPU", utilizationPercent: nil), memory: nil, disk: nil, network: nil, thermalState: .unknown, isLowPowerModeEnabled: true, uptimeSeconds: 100, limitations: ["Unavailable driver counter"])
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(SystemSnapshot.self, from: data)
        XCTAssertEqual(decoded.cpu?.logicalCoreCount, 10)
        XCTAssertEqual(decoded.cpu?.loadAverage1, 5)
        XCTAssertNil(decoded.cpu?.usagePercent)
        XCTAssertNil(decoded.gpu?.utilizationPercent)
        XCTAssertEqual(decoded.thermalState, .unknown)
        XCTAssertEqual(decoded.limitations, ["Unavailable driver counter"])
        let json = String(decoding: data, as: UTF8.self).lowercased()
        for key in ["serial", "uuid", "udid", "macaddress", "processname", "registryid"] { XCTAssertFalse(json.contains(key)) }
        requireSendable(snapshot)
    }

    private func requireSendable<T: Sendable>(_ value: T) {}
}
