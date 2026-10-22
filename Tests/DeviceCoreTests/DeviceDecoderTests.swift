import Foundation
#if !DEVICE_STANDALONE
import XCTest
#endif
@testable import DeviceCore

final class DeviceDecoderTests: XCTestCase {
    private let phone: [String: Any] = ["ProductType": "iPhone16,1", "ProductVersion": "18.3", "DeviceClass": "iPhone"]

    func testFixturePhoneBattery() {
        let value = DeviceDecoder.decode(product: phone, battery: [
            "BatteryCurrentCapacity": 73, "BatteryIsCharging": true,
            "FullyCharged": false, "ExternalConnected": true
        ], ordinal: 1)
        XCTAssertEqual(value?.kind, .iPhone)
        XCTAssertEqual(value?.productType, "iPhone16,1")
        XCTAssertEqual(value?.productVersion, "18.3")
        XCTAssertEqual(value?.batteryPercentage, 73)
        XCTAssertEqual(value?.chargingState, .charging)
        XCTAssertEqual(value?.externalPowerConnected, true)
    }

    func testFixturePadFullAndUnknownState() {
        let pad: [String: Any] = ["ProductType": "iPad14,6", "ProductVersion": "18.2.1"]
        let full = DeviceDecoder.decode(product: pad, battery: ["BatteryCurrentCapacity": 100, "FullyCharged": true], ordinal: 2)
        XCTAssertEqual(full?.kind, .iPad)
        XCTAssertEqual(full?.chargingState, .full)
        XCTAssertEqual(full?.id, "device-2")
        let unknown = DeviceDecoder.decode(product: pad, battery: ["ExternalConnected": true], ordinal: 1)
        XCTAssertNil(unknown?.chargingState)
        XCTAssertNil(unknown?.batteryPercentage)
        let notCharging = DeviceDecoder.decode(product: pad, battery: ["BatteryIsCharging": false], ordinal: 1)
        XCTAssertEqual(notCharging?.chargingState, .notCharging)
    }

    func testInvalidAndAmbiguousValuesStayAbsent() {
        for invalid: Any in [-1, 101, 10.5, true, "73", Double.infinity, Double.nan] {
            XCTAssertNil(DeviceDecoder.decode(product: phone, battery: ["BatteryCurrentCapacity": invalid], ordinal: 1)?.batteryPercentage)
        }
        let malformed = DeviceDecoder.decode(product: phone, battery: ["BatteryIsCharging": 1, "ExternalConnected": "true"], ordinal: 1)
        XCTAssertNil(malformed?.chargingState)
        XCTAssertNil(malformed?.externalPowerConnected)
        XCTAssertEqual(DeviceDecoder.decode(product: phone, battery: ["BatteryCurrentCapacity": 0], ordinal: 1)?.batteryPercentage, 0)
    }

    func testUnverifiedExtendedTelemetryNeverGuessed() {
        let value = DeviceDecoder.decode(product: phone, battery: [
            "Temperature": 2980, "CycleCount": 200, "DesignCapacity": 3000,
            "FullChargeCapacity": 2900, "CPUUsage": 97
        ], ordinal: 1)
        XCTAssertNil(value?.temperatureCelsius)
        XCTAssertNil(value?.cycleCount)
        XCTAssertNil(value?.designCapacityMAh)
        XCTAssertNil(value?.fullChargeCapacityMAh)
    }

    func testUnsupportedDeviceAndSanitization() {
        XCTAssertNil(DeviceDecoder.decode(product: ["ProductType": "AppleTV6,2", "DeviceClass": "AppleTV"], battery: [:], ordinal: 1))
        let malformed = DeviceDecoder.decode(product: ["ProductType": "PRIVATE_SENTINEL", "ProductVersion": "PRIVATE_SENTINEL", "DeviceClass": "iPhone"], battery: [:], ordinal: 1)
        XCTAssertEqual(malformed?.kind, .iPhone)
        XCTAssertNil(malformed?.productType)
        XCTAssertNil(malformed?.productVersion)
    }

    func testPrivacyAndCodable() throws {
        var product = phone
        for key in ["SerialNumber", "UniqueDeviceID", "DeviceName", "PairRecord", "PhoneNumber"] { product[key] = "PRIVATE_SENTINEL" }
        let value = DeviceDecoder.decode(product: product, battery: ["BatteryCurrentCapacity": 50, "SerialNumber": "PRIVATE_SENTINEL"], ordinal: 1)!
        let snapshot = DeviceSnapshot(status: .available, devices: [value], frameworkLoaded: true, message: "fixture")
        let data = try JSONEncoder().encode(snapshot)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("PRIVATE_SENTINEL"))
        XCTAssertEqual(try JSONDecoder().decode(DeviceSnapshot.self, from: data), snapshot)
        XCTAssertEqual(DeviceReadStatus.timedOut.rawValue, "timedOut")
    }

    func testNativeFailureCategories() {
        XCTAssertEqual(DeviceNativeFailure.status(for: Int32(bitPattern: 0xe800001a)), .requiresUnlockAndTrust)
        XCTAssertEqual(DeviceNativeFailure.status(for: Int32(bitPattern: 0xe8000025)), .requiresUnlockAndTrust)
        XCTAssertEqual(DeviceNativeFailure.status(for: Int32(bitPattern: 0xe8000096)), .requiresUnlockAndTrust)
        XCTAssertEqual(DeviceNativeFailure.status(for: Int32(bitPattern: 0xe800000c)), .timedOut)
        XCTAssertEqual(DeviceNativeFailure.status(for: -1), .unavailable)
    }

    /// Synthetic fixture: whitelisted keys in BatteryData, centi-C and mAh.
    /// Values are invented test data, not a captured device response.
    func testPackFullValuesDecodeAvailable() {
        let value = DeviceDecoder.decode(product: phone, battery: [
            "BatteryCurrentCapacity": 96, "BatteryIsCharging": false, "ExternalConnected": true
        ], diagnostics: .values([
            "Temperature": 3025, "VirtualTemperature": 2900, "CycleCount": 42,
            "DesignCapacity": 4000, "NominalChargeCapacity": 3900, "AppleRawMaxCapacity": 3950
        ]), ordinal: 1)!
        XCTAssertTrue(value.temperatureCelsius.map { abs($0 - 30.25) < 1e-9 } ?? false)
        XCTAssertEqual(value.cycleCount, 42)
        XCTAssertEqual(value.designCapacityMAh, 4000)
        XCTAssertEqual(value.fullChargeCapacityMAh, 3950)
        XCTAssertEqual(value.batteryDetailsStatus, "available")
        XCTAssertEqual(value.batteryDetailsSource, "diagnostics_relay IORegistry AppleSmartBatteryPack.BatteryData")
        XCTAssertEqual(value.batteryPercentage, 96)
        XCTAssertEqual(value.chargingState, .notCharging)
    }

    /// Top-level percentage lookalikes from the class entry must never become mAh,
    /// even when they arrive under capacity-sounding names.
    func testPackPercentKeysNeverBecomeMAh() {
        let value = DeviceDecoder.decode(product: phone, battery: [:], diagnostics: .values([
            "CycleCount": 42, "MaxCapacity": 100, "FullChargeCapacity": 100, "CurrentCapacity": 100
        ]), ordinal: 1)!
        XCTAssertEqual(value.cycleCount, 42)
        XCTAssertNil(value.designCapacityMAh)
        XCTAssertNil(value.fullChargeCapacityMAh)
        XCTAssertNil(value.temperatureCelsius)
        XCTAssertEqual(value.batteryDetailsStatus, "partial")
    }

    /// VirtualTemperature is extracted but never mapped onto the physical temperature field.
    func testPackVirtualTemperatureNeverMapsToPhysical() {
        let value = DeviceDecoder.decode(product: phone, battery: [:], diagnostics: .values([
            "VirtualTemperature": 2900, "CycleCount": 42
        ]), ordinal: 1)!
        XCTAssertNil(value.temperatureCelsius)
        XCTAssertEqual(value.cycleCount, 42)
        XCTAssertEqual(value.batteryDetailsStatus, "partial")
    }

    func testPackInvalidTemperatureRejected() {
        for invalid: NSNumber in [NSNumber(value: 99999), NSNumber(value: -5_000), NSNumber(value: 3025.5),
                                  NSNumber(value: true), NSNumber(value: Double.nan)] {
            let value = DeviceDecoder.decode(product: phone, battery: [:], diagnostics: .values([
                "Temperature": invalid, "CycleCount": 42,
                "DesignCapacity": 4000, "AppleRawMaxCapacity": 3950
            ]), ordinal: 1)!
            XCTAssertNil(value.temperatureCelsius)
            XCTAssertEqual(value.cycleCount, 42)
            XCTAssertEqual(value.designCapacityMAh, 4000)
            XCTAssertEqual(value.batteryDetailsStatus, "partial")
        }
    }

    /// Capacity validation: design needs a plausible nameplate mAh; full may decay to 0 and
    /// is trusted from the nested mAh source; only absurd inflation or reference-less
    /// percentage-scale lookalikes are rejected. Design displays independently.
    func testPackZeroAndMismatchedCapacitiesRejected() {
        // Design 0 is implausible and dropped; the real nested full value still displays.
        let zeroDesign = DeviceDecoder.decode(product: phone, battery: [:], diagnostics: .values([
            "DesignCapacity": 0, "AppleRawMaxCapacity": 3950
        ]), ordinal: 1)!
        XCTAssertNil(zeroDesign.designCapacityMAh)
        XCTAssertEqual(zeroDesign.fullChargeCapacityMAh, 3950)
        XCTAssertEqual(zeroDesign.batteryDetailsStatus, "partial")
        // Full over twice the nameplate is untrustworthy and dropped; design stays.
        let inflated = DeviceDecoder.decode(product: phone, battery: [:], diagnostics: .values([
            "DesignCapacity": 4000, "AppleRawMaxCapacity": 10000
        ]), ordinal: 1)!
        XCTAssertEqual(inflated.designCapacityMAh, 4000)
        XCTAssertNil(inflated.fullChargeCapacityMAh)
        // A severely worn pack reporting 100 mAh or 0 mAh from the nested source is real data.
        let worn = DeviceDecoder.decode(product: phone, battery: [:], diagnostics: .values([
            "DesignCapacity": 4000, "AppleRawMaxCapacity": 100
        ]), ordinal: 1)!
        XCTAssertEqual(worn.fullChargeCapacityMAh, 100)
        let dead = DeviceDecoder.decode(product: phone, battery: [:], diagnostics: .values([
            "DesignCapacity": 4000, "AppleRawMaxCapacity": 0
        ]), ordinal: 1)!
        XCTAssertEqual(dead.fullChargeCapacityMAh, 0)
        // Percentage-scale pair (100/100): design rejected as implausible, and the
        // reference-less full under 500 is rejected as a percent lookalike.
        let percentPair = DeviceDecoder.decode(product: phone, battery: [:], diagnostics: .values([
            "DesignCapacity": 100, "AppleRawMaxCapacity": 100
        ]), ordinal: 1)!
        XCTAssertNil(percentPair.designCapacityMAh)
        XCTAssertNil(percentPair.fullChargeCapacityMAh)
        XCTAssertEqual(percentPair.batteryDetailsStatus, "failed")
    }

    /// Gauge-learned NominalChargeCapacity is the documented fallback when the raw max is absent.
    func testPackNominalFallbackWhenRawMaxMissing() {
        let value = DeviceDecoder.decode(product: phone, battery: [:], diagnostics: .values([
            "Temperature": 3025, "CycleCount": 42,
            "DesignCapacity": 4000, "NominalChargeCapacity": 3900
        ]), ordinal: 1)!
        XCTAssertEqual(value.fullChargeCapacityMAh, 3900)
        XCTAssertEqual(value.designCapacityMAh, 4000)
        XCTAssertEqual(value.batteryDetailsStatus, "available")
    }

    /// The reader copies whitelisted scalars from the explicit BatteryData path only.
    func testPackExtractionNestedPathOnly() {
        let response: [String: Any] = [
            "Status": "Success",
            "Diagnostics": ["IORegistry": [
                "Temperature": 9999, "MaxCapacity": 100, "DesignCapacity": 1,
                "BatteryData": [
                    "Temperature": 3025, "CycleCount": 42, "MaxCapacity": 100,
                    "Amperage": -120, "SerialNumber": "PRIVATE_SENTINEL"
                ],
                "Other": ["DesignCapacity": 4000]
            ]]
        ]
        let values = DiagnosticsBatteryReader.extractPackValues(response: response)
        XCTAssertEqual(values.count, 2)
        XCTAssertEqual(values["Temperature"]?.intValue, 3025)
        XCTAssertEqual(values["CycleCount"]?.intValue, 42)
        XCTAssertNil(values["DesignCapacity"])
        XCTAssertNil(values["MaxCapacity"])
        XCTAssertNil(values["Amperage"])
        for broken: [String: Any] in [
            ["Status": "Success"],
            ["Diagnostics": ["IORegistry": [:]]],
            ["Diagnostics": ["IORegistry": ["BatteryData": "not-a-dict"]]],
            ["Diagnostics": "not-a-dict"]
        ] {
            XCTAssertTrue(DiagnosticsBatteryReader.extractPackValues(response: broken).isEmpty)
        }
    }

    func testDiagnosticsCycleCountFilled() {
        let value = DeviceDecoder.decode(product: phone, battery: [
            "BatteryCurrentCapacity": 33, "BatteryIsCharging": true, "ExternalConnected": true
        ], diagnostics: .values(["CycleCount": 42]), ordinal: 1)!
        XCTAssertEqual(value.cycleCount, 42)
        XCTAssertEqual(value.batteryDetailsStatus, "partial")
        XCTAssertEqual(value.batteryDetailsSource, "diagnostics_relay IORegistry AppleSmartBatteryPack.BatteryData")
        XCTAssertNil(value.temperatureCelsius)
        XCTAssertNil(value.designCapacityMAh)
        XCTAssertNil(value.fullChargeCapacityMAh)
        XCTAssertEqual(value.batteryPercentage, 33)
        XCTAssertEqual(value.chargingState, .charging)
    }

    func testDiagnosticsInvalidCycleRejectedAsFailed() {
        let invalids: [NSNumber] = [NSNumber(value: -1), NSNumber(value: 100_001), NSNumber(value: 1.5),
                                    NSNumber(value: true), NSNumber(value: Double.nan)]
        for invalid in invalids {
            let value = DeviceDecoder.decode(product: phone, battery: [:],
                                             diagnostics: .values(["CycleCount": invalid]), ordinal: 1)
            XCTAssertNil(value?.cycleCount)
            XCTAssertEqual(value?.batteryDetailsStatus, "failed")
            XCTAssertEqual(value?.batteryDetailsSource, "diagnostics_relay IORegistry AppleSmartBatteryPack.BatteryData")
        }
    }

    func testDiagnosticsFailedKeepsBasicAndNotAttemptedStaysNil() {
        let failed = DeviceDecoder.decode(product: phone, battery: [
            "BatteryCurrentCapacity": 55, "ExternalConnected": false
        ], diagnostics: .failed, ordinal: 1)!
        XCTAssertEqual(failed.batteryDetailsStatus, "failed")
        XCTAssertEqual(failed.batteryDetailsSource, "diagnostics_relay IORegistry AppleSmartBatteryPack.BatteryData")
        XCTAssertEqual(failed.batteryPercentage, 55)
        XCTAssertEqual(failed.externalPowerConnected, false)
        XCTAssertNil(failed.cycleCount)
        let skipped = DeviceDecoder.decode(product: phone, battery: ["BatteryCurrentCapacity": 55], ordinal: 1)!
        XCTAssertNil(skipped.batteryDetailsStatus)
        XCTAssertNil(skipped.batteryDetailsSource)
        XCTAssertNil(skipped.cycleCount)
    }
}
