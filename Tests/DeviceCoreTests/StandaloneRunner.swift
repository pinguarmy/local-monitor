// Compile alongside both test files with -D DEVICE_STANDALONE -parse-as-library.
#if DEVICE_STANDALONE
import Foundation
import Darwin
@testable import DeviceCore

class XCTestCase {}
private var assertions = 0
private var failures = 0
private func check(_ condition: Bool, _ message: String, file: StaticString, line: UInt) {
    assertions += 1
    if !condition { failures += 1; print("FAIL \(file):\(line) \(message)") }
}
func XCTAssertEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #filePath, line: UInt = #line) {
    check(actual == expected, "\(actual) != \(expected)", file: file, line: line)
}
func XCTAssertTrue(_ actual: Bool, file: StaticString = #filePath, line: UInt = #line) {
    check(actual, "expected true", file: file, line: line)
}
func XCTAssertFalse(_ actual: Bool, file: StaticString = #filePath, line: UInt = #line) {
    check(!actual, "expected false", file: file, line: line)
}
func XCTAssertNil(_ actual: Any?, file: StaticString = #filePath, line: UInt = #line) {
    check(actual == nil, "expected nil", file: file, line: line)
}

@main struct DeviceStandaloneRunner {
    static func main() async {
        if CommandLine.arguments.contains("--probe") {
            let result = await DeviceReader().read(timeout: 5)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            do { print(String(decoding: try encoder.encode(result), as: UTF8.self)) }
            catch { print("snapshot encode failed"); exit(1) }
            return
        }
        let decoder = DeviceDecoderTests()
        let reader = DeviceReaderTests()
        let tests: [(String, () throws -> Void)] = [
            ("phone fixture", decoder.testFixturePhoneBattery),
            ("pad fixture and unknown charging", decoder.testFixturePadFullAndUnknownState),
            ("invalid values", decoder.testInvalidAndAmbiguousValuesStayAbsent),
            ("unverified telemetry", decoder.testUnverifiedExtendedTelemetryNeverGuessed),
            ("unsupported and sanitized", decoder.testUnsupportedDeviceAndSanitization),
            ("privacy and Codable", decoder.testPrivacyAndCodable),
            ("native error categories", decoder.testNativeFailureCategories),
            ("pack full values available", decoder.testPackFullValuesDecodeAvailable),
            ("pack percent never mAh", decoder.testPackPercentKeysNeverBecomeMAh),
            ("pack virtual temp not physical", decoder.testPackVirtualTemperatureNeverMapsToPhysical),
            ("pack invalid temperature", decoder.testPackInvalidTemperatureRejected),
            ("pack zero and mismatched capacity", decoder.testPackZeroAndMismatchedCapacitiesRejected),
            ("pack nominal fallback", decoder.testPackNominalFallbackWhenRawMaxMissing),
            ("pack extraction nested path", decoder.testPackExtractionNestedPathOnly),
            ("diagnostics cycle filled", decoder.testDiagnosticsCycleCountFilled),
            ("diagnostics invalid cycle", decoder.testDiagnosticsInvalidCycleRejectedAsFailed),
            ("diagnostics failed keeps basic", decoder.testDiagnosticsFailedKeepsBasicAndNotAttemptedStaysNil),
            ("missing framework and symbols", reader.testMissingFrameworkAndSymbolsDowngrade)
        ]
        for (name, test) in tests {
            let before = failures
            do { try test() } catch { failures += 1; print("FAIL \(name): \(error)") }
            print("\(before == failures ? "PASS" : "FAIL") \(name)")
        }
        var before = failures
        await reader.testDeadlineDoesNotAccumulateNativeWork()
        print("\(before == failures ? "PASS" : "FAIL") deadline and reentry")
        before = failures
        await reader.testSuccessfulReadAndQuarantinedGate()
        print("\(before == failures ? "PASS" : "FAIL") success and quarantine")
        print("\(tests.count + 2) test cases, \(assertions) assertions, \(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }
}
#endif
