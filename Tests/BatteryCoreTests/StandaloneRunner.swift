// Excluded from the SwiftPM test target. Compile with -D BATTERY_STANDALONE -parse-as-library
// alongside BatteryDecoderTests.swift when the local toolchain does not contain XCTest.
#if BATTERY_STANDALONE
import Foundation
import Darwin

class XCTestCase {}
private var assertionCount = 0
private var failureCount = 0
private func check(_ success: Bool, _ message: String, file: StaticString, line: UInt) {
    assertionCount += 1
    if !success {
        failureCount += 1
        print("FAIL \(file):\(line): \(message)")
    }
}
func XCTAssertEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #filePath, line: UInt = #line) {
    check(actual == expected, "\(actual) != \(expected)", file: file, line: line)
}
func XCTAssertEqual(_ actual: Double, _ expected: Double, accuracy: Double, file: StaticString = #filePath, line: UInt = #line) {
    check(abs(actual - expected) <= accuracy, "\(actual) != \(expected), accuracy \(accuracy)", file: file, line: line)
}
func XCTAssertGreaterThan<T: Comparable>(_ actual: T, _ expected: T, file: StaticString = #filePath, line: UInt = #line) {
    check(actual > expected, "\(actual) is not greater than \(expected)", file: file, line: line)
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
    static func main() {
        let tests = BatteryDecoderTests()
        let cases: [(String, () throws -> Void)] = [
            ("percentage normalization", tests.testPercentageNormalizesAgainstMaximum),
            ("AC is not charging", tests.testACAttachmentDoesNotImplyChargingOrFull),
            ("unknown charge states", tests.testMissingChargingAndChargedRemainUnknown),
            ("raw capacity priority", tests.testRawCapacityTakesPriorityOverPercentageMaxCapacity),
            ("capacity unit safety", tests.testPercentageCapacityIsNeverMixedWithMAh),
            ("legacy and nested capacities", tests.testLegacyAndSanitizedNestedCapacities),
            ("zero preservation", tests.testZeroValuesAreNotMissing),
            ("temperature checks", tests.testTemperatureConventionAndAmbiguity),
            ("signed and two's complement current", tests.testSignedAndUnsignedTwosComplementCurrent),
            ("invalid telemetry", tests.testInvalidTelemetryIsOmittedWithoutTrapping),
            ("external and absent batteries", tests.testExternalSourcesAreIgnoredAndAbsentBatteryHasNoMeasurements),
            ("registry without official status", tests.testRegistryCanSupplyMeasurementsWithoutInventingOfficialState),
            ("verified temperature paths and priority", tests.testVerifiedPackTemperatureAndOfficialTemperaturePriority),
            ("current encoding ambiguity", tests.testCurrentNeverGuessesUnsignedWidth),
            ("availability and read failures", tests.testAvailabilitySeparatesAbsenceFromReadFailures),
            ("IOPS electrical fallback", tests.testPublicIOPSElectricalFallbackHasDocumentedUnits),
            ("old JSON and new snapshot fields", tests.testSnapshotOldJSONAndNewFieldsRoundTrip),
            ("condition, privacy, Codable", tests.testConditionPrefersSpecificOfficialConditionAndNeverLeaksIdentifiers)
        ]
        for (name, test) in cases {
            let before = failureCount
            do { try test() } catch { failureCount += 1; print("FAIL \(name): \(error)") }
            print("\(before == failureCount ? "PASS" : "FAIL") \(name)")
        }
        print("\(cases.count) test cases, \(assertionCount) assertions, \(failureCount) failures")
        exit(failureCount == 0 ? 0 : 1)
    }
}
#endif
