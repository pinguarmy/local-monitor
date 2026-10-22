import Foundation
#if BATTERY_STANDALONE
import BatteryCore
#else
import XCTest
@testable import BatteryCore
#endif

final class BatteryDecoderTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_700_000_000)
    private func source(_ extra: [String: Any] = [:]) -> [String: Any] {
        var result: [String: Any] = [
            "Type": "InternalBattery", "Is Present": true, "Current Capacity": 40,
            "Max Capacity": 80, "Power Source State": "AC Power", "Is Charging": false,
            "Is Charged": false, "BatteryHealth": "Good"
        ]
        result.merge(extra) { _, new in new }
        return result
    }
    private func decode(
        _ registry: [String: Any] = [:], _ extra: [String: Any] = [:],
        unit: BatteryTemperatureUnit? = nil, encoding: BatteryAmperageEncoding = .signedMilliAmps
    ) -> BatterySnapshot {
        BatteryDecoder.decode(powerSources: [source(extra)], registry: registry, date: date,
                              registryTemperatureUnit: unit, amperageEncoding: encoding)
    }

    func testPercentageNormalizesAgainstMaximum() {
        XCTAssertEqual(decode().percentage, 50)
        XCTAssertEqual(decode([:], ["Current Capacity": 1, "Max Capacity": 3]).percentage, 33)
        XCTAssertEqual(decode([:], ["Current Capacity": 120, "Max Capacity": 100]).percentage, 100)
        XCTAssertNil(decode([:], ["Current Capacity": -1]).percentage)
        XCTAssertNil(decode([:], ["Max Capacity": 0]).percentage)
    }

    func testACAttachmentDoesNotImplyChargingOrFull() {
        let snapshot = decode([:], ["Current Capacity": 100, "Max Capacity": 100])
        XCTAssertEqual(snapshot.powerSource, "AC Power")
        XCTAssertEqual(snapshot.isCharging, false)
        XCTAssertEqual(snapshot.isCharged, false)
        XCTAssertEqual(snapshot.percentage, 100)
    }

    func testMissingChargingAndChargedRemainUnknown() {
        var input = source()
        input.removeValue(forKey: "Is Charging")
        input.removeValue(forKey: "Is Charged")
        let snapshot = BatteryDecoder.decode(powerSources: [input], registry: [:], date: date)
        XCTAssertNil(snapshot.isCharging)
        XCTAssertNil(snapshot.isCharged)
    }

    func testRawCapacityTakesPriorityOverPercentageMaxCapacity() {
        let snapshot = decode(["DesignCapacity": 6000, "AppleRawMaxCapacity": 5400, "MaxCapacity": 90])
        XCTAssertEqual(snapshot.maximumCapacityMAh, 5400)
        XCTAssertEqual(snapshot.designCapacityMAh, 6000)
        XCTAssertEqual(snapshot.healthPercent, 90)
    }

    func testPercentageCapacityIsNeverMixedWithMAh() {
        let snapshot = decode(["DesignCapacity": 6000, "MaxCapacity": 95])
        XCTAssertNil(snapshot.maximumCapacityMAh)
        XCTAssertNil(snapshot.healthPercent)
        XCTAssertTrue(snapshot.limitations.contains { $0.contains("ambiguous") })
    }

    func testLegacyAndSanitizedNestedCapacities() {
        XCTAssertEqual(decode(["DesignCapacity": 6000, "MaxCapacity": 5000]).maximumCapacityMAh, 5000)
        let nested = decode(["MaxCapacity": 100, "BatteryData": ["FullChargeCapacity": 6280, "DesignCapacity": 6249]])
        XCTAssertEqual(nested.maximumCapacityMAh, 6280)
        XCTAssertEqual(nested.designCapacityMAh, 6249)
        XCTAssertGreaterThan(nested.healthPercent ?? 0, 100)
        XCTAssertNil(decode(["MaxCapacity": 5000]).maximumCapacityMAh)
    }

    func testZeroValuesAreNotMissing() {
        let snapshot = decode([
            "AppleRawMaxCapacity": 0, "DesignCapacity": 6000, "CycleCount": 0,
            "Temperature": 0, "Voltage": 0, "Amperage": 0
        ], ["Current Capacity": 0], unit: .centiCelsius)
        XCTAssertEqual(snapshot.percentage, 0)
        XCTAssertEqual(snapshot.maximumCapacityMAh, 0)
        XCTAssertEqual(snapshot.healthPercent, 0)
        XCTAssertEqual(snapshot.cycleCount, 0)
        XCTAssertEqual(snapshot.temperatureCelsius, 0)
        XCTAssertEqual(snapshot.voltageVolts, 0)
        XCTAssertEqual(snapshot.amperageMA, 0)
        XCTAssertEqual(snapshot.powerWatts, 0)
        XCTAssertNil(decode(["DesignCapacity": 0, "AppleRawMaxCapacity": 0]).healthPercent)
    }

    func testTemperatureConventionAndAmbiguity() {
        let snapshot = decode(["Temperature": 2981], unit: .centiCelsius)
        XCTAssertEqual(snapshot.temperatureCelsius ?? -999, 29.81, accuracy: 0.0001)
        XCTAssertEqual(snapshot.temperatureSource, "AppleSmartBattery.Temperature")
        XCTAssertNil(decode(["Temperature": 2981]).temperatureCelsius)
        XCTAssertNil(decode(["Temperature": 30]).temperatureCelsius)
        XCTAssertNil(decode(["Temperature": 65535], unit: .centiCelsius).temperatureCelsius)
        XCTAssertEqual(decode(["Temperature": -1000], unit: .centiCelsius).temperatureCelsius, -10)
        XCTAssertEqual(decode(["Temperature": 2981], unit: .deciKelvin).temperatureCelsius ?? -999, 24.95, accuracy: 0.0001)
        XCTAssertEqual(decode(["Temperature": 30], unit: .celsius).temperatureCelsius, 30)
    }

    func testSignedAndUnsignedTwosComplementCurrent() {
        let values: [(Any, BatteryAmperageEncoding)] = [
            (-1200, .signedMilliAmps), (NSNumber(value: UInt16.max - 1199), .unsignedTwosComplement16),
            (NSNumber(value: UInt32.max - 1199), .unsignedTwosComplement32),
            (NSNumber(value: UInt64.max - 1199), .unsignedTwosComplement64)
        ]
        for (value, encoding) in values {
            let snapshot = decode(["Amperage": value, "Voltage": 12000], encoding: encoding)
            XCTAssertEqual(snapshot.amperageMA, -1200)
            XCTAssertEqual(snapshot.powerWatts ?? 999, -14.4, accuracy: 0.0001)
        }
        XCTAssertEqual(decode(["Amperage": NSNumber(value: UInt64.max)], encoding: .unsignedTwosComplement64).amperageMA, -1)
        XCTAssertEqual(decode(["Amperage": 1500, "Voltage": 12000]).powerWatts, 18)
    }

    func testInvalidTelemetryIsOmittedWithoutTrapping() {
        let snapshot = decode([
            "DesignCapacity": -1, "AppleRawMaxCapacity": Double.infinity,
            "CycleCount": -3, "Temperature": Double.nan, "Voltage": 100000,
            "Amperage": NSNumber(value: UInt64.max / 2)
        ], ["Current Capacity": Double.nan])
        XCTAssertNil(snapshot.percentage)
        XCTAssertNil(snapshot.maximumCapacityMAh)
        XCTAssertNil(snapshot.designCapacityMAh)
        XCTAssertNil(snapshot.cycleCount)
        XCTAssertNil(snapshot.temperatureCelsius)
        XCTAssertNil(snapshot.voltageVolts)
        XCTAssertNil(snapshot.amperageMA)
        XCTAssertNil(snapshot.powerWatts)
        XCTAssertFalse(snapshot.limitations.isEmpty)
        XCTAssertNil(decode(["Amperage": 1.5]).amperageMA)
        XCTAssertNil(decode(["Amperage": 100000]).amperageMA)
        XCTAssertNil(decode(["Amperage": -30001]).amperageMA)
        XCTAssertNil(decode(["Voltage": true]).voltageVolts)
        XCTAssertNil(decode(["CycleCount": "0"]).cycleCount)
    }

    func testExternalSourcesAreIgnoredAndAbsentBatteryHasNoMeasurements() {
        let ups: [String: Any] = ["Type": "UPS", "Current Capacity": 99, "Max Capacity": 100]
        let snapshot = BatteryDecoder.decode(powerSources: [ups, source()], registry: [:], date: date)
        XCTAssertEqual(snapshot.percentage, 50)
        let absent = BatteryDecoder.decode(powerSources: [source(["Is Present": false])], registry: ["Voltage": 12000], date: date)
        XCTAssertFalse(absent.isPresent)
        XCTAssertNil(absent.voltageVolts)
        XCTAssertNil(absent.percentage)
        let missing = BatteryDecoder.decode(powerSources: [ups], registry: [:], date: date)
        XCTAssertFalse(missing.isPresent)
        XCTAssertEqual(missing.powerSource, "Unknown")
    }

    func testRegistryCanSupplyMeasurementsWithoutInventingOfficialState() {
        let snapshot = BatteryDecoder.decode(powerSources: [], registry: ["Voltage": 12000, "Amperage": 0], date: date)
        XCTAssertTrue(snapshot.isPresent)
        XCTAssertNil(snapshot.percentage)
        XCTAssertNil(snapshot.isCharging)
        XCTAssertEqual(snapshot.powerSource, "Unknown")
        XCTAssertEqual(snapshot.powerWatts, 0)
    }

    func testVerifiedPackTemperatureAndOfficialTemperaturePriority() {
        let registry: [String: Any] = ["BatteryPackData": ["Temperature": 2859, "SerialNumber": "PRIVATE-PACK"]]
        let pack = decode(registry)
        XCTAssertEqual(pack.temperatureCelsius, 28.59)
        XCTAssertEqual(pack.temperatureSource, "AppleSmartBatteryPack.BatteryData.Temperature")
        XCTAssertTrue(pack.limitations.contains { $0.contains("0.01 °C") })
        let official = decode(registry, ["Temperature": 25])
        XCTAssertEqual(official.temperatureCelsius, 25)
        XCTAssertEqual(official.temperatureSource, "IOPowerSources.Temperature")
        XCTAssertEqual(decode(registry, ["Temperature": 0]).temperatureCelsius, 0)
        XCTAssertEqual(decode(registry, ["Temperature": 999]).temperatureCelsius, 28.59)
        XCTAssertNil(decode(["VirtualTemperature": 2859]).temperatureCelsius)
        XCTAssertNil(decode(["BatteryPackData": ["VirtualTemperature": 2859]]).temperatureCelsius)
        XCTAssertNil(decode(["BatteryPackData": ["Temperature": true]]).temperatureCelsius)
        XCTAssertNil(decode(["BatteryPackData": ["Temperature": 10001]]).temperatureCelsius)
        XCTAssertEqual(decode(["BatteryPackData": ["Temperature": -2000]]).temperatureCelsius, -20)
        XCTAssertEqual(decode(["BatteryPackData": ["Temperature": 10000]]).temperatureCelsius, 100)
        XCTAssertNil(decode(["BatteryPackData": ["Temperature": -2001]]).temperatureCelsius)
        XCTAssertNil(decode(["BatteryPackData": ["Temperature": Double.nan]]).temperatureSource)
    }

    func testCurrentNeverGuessesUnsignedWidth() {
        for value: Any in [40000, 64336, NSNumber(value: UInt16.max - 1199), NSNumber(value: UInt32.max - 1199), NSNumber(value: UInt64.max - 1199)] {
            let snapshot = decode(["Amperage": value, "Voltage": 12000])
            XCTAssertNil(snapshot.amperageMA)
            XCTAssertNil(snapshot.powerWatts)
            XCTAssertTrue(snapshot.limitations.contains { $0.contains("explicit encoding") })
        }
        XCTAssertEqual(decode(["Amperage": 40000], encoding: .unsignedTwosComplement16).amperageMA, -25536)
        XCTAssertNil(decode(["Amperage": 65536], encoding: .unsignedTwosComplement16).amperageMA)
        XCTAssertNil(decode(["Amperage": -1200], encoding: .unsignedTwosComplement16).amperageMA)
        XCTAssertNil(decode(["Amperage": NSNumber(value: UInt64.max)], encoding: .unsignedTwosComplement32).amperageMA)
        XCTAssertEqual(decode(["Amperage": 30000]).amperageMA, 30000)
        XCTAssertEqual(decode(["Amperage": -30000]).amperageMA, -30000)
        XCTAssertNil(decode(["Amperage": true]).amperageMA)
        XCTAssertNil(decode(["Amperage": "64336"], encoding: .unsignedTwosComplement16).amperageMA)
    }

    func testAvailabilitySeparatesAbsenceFromReadFailures() {
        func sample(_ sources: [[String: Any]], _ registry: [String: Any], _ errors: [BatteryReadError]) -> BatterySnapshot {
            BatteryDecoder.decode(powerSources: sources, registry: registry, date: date, readErrors: errors)
        }
        let failed = sample([], [:], [.powerSourcesUnavailable, .registryUnavailable])
        XCTAssertEqual(failed.availability, .unknown)
        XCTAssertFalse(failed.isPresent)
        XCTAssertEqual(failed.readErrors, [.powerSourcesUnavailable, .registryUnavailable])
        XCTAssertTrue(failed.limitations.contains { $0.contains("not evidence of no battery") })
        XCTAssertEqual(sample([], [:], []).availability, .absent)
        XCTAssertEqual(sample([], [:], [.powerSourceDescriptionUnavailable]).availability, .unknown)
        let partial = sample([source()], [:], [.registryUnavailable])
        XCTAssertTrue(partial.isPresent)
        XCTAssertEqual(partial.availability, .present)
        XCTAssertEqual(partial.percentage, 50)
        XCTAssertEqual(partial.readErrors, [.registryUnavailable])
        XCTAssertEqual(sample([], ["BatteryInstalled": true], [.powerSourcesUnavailable]).availability, .present)
        XCTAssertEqual(sample([], ["BatteryInstalled": false, "Voltage": 0], [.powerSourcesUnavailable]).availability, .absent)
        let absent = sample([source(["Is Present": false])], ["BatteryPackData": ["Temperature": 2859]], [.registryUnavailable])
        XCTAssertEqual(absent.availability, .absent)
        XCTAssertNil(absent.temperatureCelsius)
        XCTAssertNil(absent.temperatureSource)
    }

    func testPublicIOPSElectricalFallbackHasDocumentedUnits() {
        let fallback = decode([:], ["Voltage": 12000, "Current": -500])
        XCTAssertEqual(fallback.voltageVolts, 12)
        XCTAssertEqual(fallback.amperageMA, -500)
        XCTAssertEqual(fallback.powerWatts, -6)
        let primary = decode(["Voltage": 11000, "Amperage": 100], ["Voltage": 12000, "Current": -500])
        XCTAssertEqual(primary.powerWatts, 1.1)
        XCTAssertEqual(decode(["Voltage": 100000, "Amperage": 40000], ["Voltage": 12000, "Current": -500]).powerWatts, -6)
        XCTAssertNil(decode([:], ["Voltage": true, "Current": 40000]).powerWatts)
    }

    func testSnapshotOldJSONAndNewFieldsRoundTrip() throws {
        let old = Data("{\"timestamp\":0,\"isPresent\":false,\"powerSource\":\"Unknown\",\"limitations\":[]}".utf8)
        let decoded = try JSONDecoder().decode(BatterySnapshot.self, from: old)
        XCTAssertEqual(decoded.availability, .unknown)
        XCTAssertEqual(decoded.readErrors, [])
        XCTAssertNil(decoded.temperatureSource)
        XCTAssertNil(decoded.reportedHealthPercent)
        let oldPresent = Data("{\"timestamp\":0,\"isPresent\":true,\"powerSource\":\"AC Power\",\"limitations\":[]}".utf8)
        XCTAssertEqual(try JSONDecoder().decode(BatterySnapshot.self, from: oldPresent).availability, .present)
        let current = BatterySnapshot(timestamp: date, isPresent: false, availability: .unknown, readErrors: [.registryUnavailable])
        XCTAssertEqual(try JSONDecoder().decode(BatterySnapshot.self, from: JSONEncoder().encode(current)), current)
        XCTAssertEqual(BatterySnapshot(isPresent: false).availability, .absent)
        XCTAssertEqual(BatterySnapshot(isPresent: true).availability, .present)
        XCTAssertFalse(BatterySnapshot(isPresent: true, availability: .unknown).isPresent)
    }

    func testConditionPrefersSpecificOfficialConditionAndNeverLeaksIdentifiers() throws {
        let snapshot = decode([
            "SerialNumber": "DO-NOT-COLLECT", "DeviceID": "PRIVATE",
            "BatteryPackData": ["Temperature": 2859, "SerialNumber": "PRIVATE-PACK"]
        ], ["BatteryHealthCondition": "Service Recommended"])
        XCTAssertEqual(snapshot.condition, "Service Recommended")
        let data = try JSONEncoder().encode(snapshot)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("DO-NOT-COLLECT"))
        XCTAssertFalse(text.contains("PRIVATE"))
        XCTAssertEqual(try JSONDecoder().decode(BatterySnapshot.self, from: data), snapshot)
        XCTAssertEqual(snapshot.timestamp, date)
    }
}
