// Compile with -D SYSTEM_STANDALONE -parse-as-library alongside SystemCoreTests.swift.
// --live also performs exactly three native reads, with one 2-second interval and a reset.
#if SYSTEM_STANDALONE
import Foundation
import Darwin
import SystemCore

class XCTestCase {}
private var assertionCount = 0
private var failureCount = 0
private func check(_ success: Bool, _ message: String, file: StaticString, line: UInt) {
    assertionCount += 1
    if !success { failureCount += 1; print("FAIL \(file):\(line): \(message)") }
}
func XCTAssertEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #filePath, line: UInt = #line) {
    check(actual == expected, "\(actual) != \(expected)", file: file, line: line)
}
func XCTAssertEqual(_ actual: Double, _ expected: Double, accuracy: Double, file: StaticString = #filePath, line: UInt = #line) {
    check(abs(actual - expected) <= accuracy, "\(actual) != \(expected), accuracy \(accuracy)", file: file, line: line)
}
func XCTAssertTrue(_ actual: Bool, file: StaticString = #filePath, line: UInt = #line) {
    check(actual, "expected true", file: file, line: line)
}
func XCTAssertFalse(_ actual: Bool, file: StaticString = #filePath, line: UInt = #line) {
    check(!actual, "expected false", file: file, line: line)
}
func XCTAssertNil(_ actual: Any?, file: StaticString = #filePath, line: UInt = #line) {
    check(actual == nil, "expected nil, got \(String(describing: actual))", file: file, line: line)
}

@main
struct StandaloneRunner {
    static func main() throws {
        let tests = SystemCoreTests()
        let cases: [(String, () throws -> Void)] = [
            ("CPU baseline and busy ticks", tests.testCPUNeedsTwoSamplesAndCountsNiceAsBusy),
            ("CPU reset and wrap", tests.testCPUCounterResetAndWrapCannotUnderflow),
            ("memory formula", tests.testMemoryFormulaDoesNotDoubleCountFileCacheOrSpeculativePages),
            ("memory saturation", tests.testMemoryCountersAreClampedWithoutOverflow),
            ("kernel pressure levels", tests.testPressureUsesKernelLevelsNotUsedPercentage),
            ("network baseline and interval", tests.testNetworkNeedsBaselineAndUsesInterval),
            ("per-interface counter reset", tests.testNetworkRejectsResetEvenWhenAggregateIncreases),
            ("interface changes and invalid time", tests.testNetworkInterfaceChangesAndInvalidTimeRebaseline),
            ("network deduplication and 64-bit counters", tests.testNetworkDeduplicatesAndRetains64BitCounters),
            ("network loopback and overlay exclusion", tests.testNetworkFilterExcludesLoopbackAndOverlayDuplicates),
            ("GPU percentage whitelist", tests.testGPUAcceptsOnlyWhitelistedFinitePercentages),
            ("saturating arithmetic", tests.testSaturatingArithmeticNeverTraps),
            ("snapshot Codable, unknowns and privacy", tests.testSnapshotRoundTripKeepsUnknownsAndNoIdentifiers)
        ]
        for (name, test) in cases {
            let before = failureCount
            do { try test() } catch { failureCount += 1; print("FAIL \(name): \(error)") }
            print("\(before == failureCount ? "PASS" : "FAIL") \(name)")
        }
        if CommandLine.arguments.contains("--live") { try verifyLive() }
        print("\(cases.count) deterministic test cases, \(assertionCount) assertions, \(failureCount) failures")
        exit(failureCount == 0 ? 0 : 1)
    }

    private static func verifyLive() throws {
        let reader = SystemReader()
        let start = ProcessInfo.processInfo.systemUptime
        let first = reader.read()
        let firstCost = ProcessInfo.processInfo.systemUptime - start
        XCTAssertNil(first.cpu?.usagePercent)
        XCTAssertNil(first.network?.downloadBytesPerSecond)
        XCTAssertNil(first.network?.intervalSeconds)
        // This one-shot pause belongs to the validation executable, never to SystemReader.
        Thread.sleep(forTimeInterval: 2)
        let secondStart = ProcessInfo.processInfo.systemUptime
        let second = reader.read()
        let secondCost = ProcessInfo.processInfo.systemUptime - secondStart
        XCTAssertTrue((second.cpu?.logicalCoreCount ?? 0) > 0)
        XCTAssertTrue(second.uptimeSeconds > first.uptimeSeconds)
        if let utilization = second.cpu?.usagePercent { XCTAssertTrue((0...100).contains(utilization)) }
        if let memory = second.memory {
            XCTAssertTrue(memory.totalBytes > 0)
            XCTAssertEqual(memory.usedBytes + memory.availableBytes, memory.totalBytes)
            XCTAssertTrue(memory.compressedBytes <= memory.usedBytes)
        }
        if let disk = second.disk {
            XCTAssertTrue(disk.totalBytes > 0)
            XCTAssertTrue(disk.availableBytes <= disk.freeBytes && disk.freeBytes <= disk.totalBytes)
        }
        if let network = second.network, let interval = network.intervalSeconds {
            XCTAssertTrue(interval >= 2)
            XCTAssertTrue((network.downloadBytesPerSecond ?? -1) >= 0)
            XCTAssertTrue((network.uploadBytesPerSecond ?? -1) >= 0)
        }
        reader.resetBaselines()
        let reset = reader.read()
        XCTAssertNil(reset.cpu?.usagePercent)
        XCTAssertNil(reset.network?.downloadBytesPerSecond)
        XCTAssertNil(reset.network?.uploadBytesPerSecond)
        XCTAssertNil(reset.network?.intervalSeconds)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(second)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        _ = try decoder.decode(SystemSnapshot.self, from: data)
        print("LIVE first_read_ms=\(firstCost * 1000) second_read_ms=\(secondCost * 1000)")
        print(String(decoding: data, as: UTF8.self))
        print("PASS live baseline, interval, reset and JSON validation")
    }
}
#endif
