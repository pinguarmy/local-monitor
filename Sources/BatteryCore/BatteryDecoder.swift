import Foundation
import CoreFoundation

/// A caller must know the source's unit, not infer it from a plausible numeric range.
public enum BatteryTemperatureUnit: Sendable {
    case celsius, centiCelsius, deciKelvin
}

/// NSNumber bridging can erase the original integer width. Unsigned bit patterns require
/// explicit provenance supplied by the caller. The reader uses signed mA, never guessed widths.
public enum BatteryAmperageEncoding: Sendable {
    case signedMilliAmps, unsignedTwosComplement16, unsignedTwosComplement32, unsignedTwosComplement64
}

/// Pure decoding of allowlisted values. Never uses a registry percentage as an mAh capacity.
public enum BatteryDecoder {
    public static func decode(
        powerSources: [[String: Any]], registry: [String: Any], date: Date,
        readErrors: [BatteryReadError] = [], registryTemperatureUnit: BatteryTemperatureUnit? = nil,
        amperageEncoding: BatteryAmperageEncoding = .signedMilliAmps
    ) -> BatterySnapshot {
        var notes: [String] = []
        let internalSources = powerSources.filter {
            ($0["Type"] as? String) == "InternalBattery" || ($0["Transport Type"] as? String) == "Internal"
        }
        let source = internalSources.first { boolean($0["Is Present"]) != false } ?? internalSources.first
        if internalSources.count > 1 { notes.append("Multiple internal batteries were reported; only the first present battery is shown.") }
        let sourcePresence = boolean(source?["Is Present"])
        let registryPresence = boolean(registry["BatteryInstalled"])
        // A successful empty query establishes absence. Failed queries must not look like
        // a desktop Mac with no battery. Registry contents alone remain a legacy fallback.
        let availability: BatteryAvailability
        if sourcePresence == true || (sourcePresence == nil && registryPresence == true) {
            availability = .present
        } else if sourcePresence == false || registryPresence == false {
            availability = .absent
        } else if source != nil || !registry.isEmpty {
            availability = .present
        } else {
            availability = readErrors.isEmpty ? .absent : .unknown
        }
        if source == nil { notes.append("IOPowerSources did not provide an internal battery; charge and power-source status are unavailable.") }
        if registry.isEmpty { notes.append("AppleSmartBattery registry measurements are unavailable.") }
        for error in readErrors { notes.append("Battery read error: \(error.rawValue).") }
        if availability != .present {
            notes.append(availability == .absent ? "No present internal battery was reported; measurements are unavailable." : "Battery availability is unknown because reads failed; this is not evidence of no battery.")
            return BatterySnapshot(timestamp: date, isPresent: false, limitations: notes, availability: availability, readErrors: readErrors)
        }

        var percentage: Int?
        if let current = number(source?["Current Capacity"]), let maximum = number(source?["Max Capacity"]),
           current >= 0, maximum > 0 {
            let normalized = current / maximum * 100
            if normalized.isFinite {
                percentage = Int(min(100, max(0, normalized)).rounded())
                if current > maximum { notes.append("IOPowerSources current capacity exceeded its maximum; percentage was clamped to 100.") }
            }
        }
        if percentage == nil { notes.append("Battery percentage is unavailable because IOPowerSources capacity values are missing or invalid.") }
        let reportedPower = source?["Power Source State"] as? String
        let power = ["AC Power", "Battery Power", "Off Line"].contains(reportedPower ?? "") ? reportedPower! : "Unknown"
        if power == "Unknown" { notes.append("The active power source is unavailable.") }
        let charging = boolean(source?["Is Charging"])
        let charged = boolean(source?["Is Charged"])
        if charging == nil { notes.append("IOPowerSources charging state is unavailable; AC attachment alone does not imply charging.") }
        if charged == nil { notes.append("IOPowerSources fully-charged state is unavailable; it is not inferred from percentage.") }
        let condition = nonemptyString(source?["BatteryHealthCondition"]) ?? nonemptyString(source?["BatteryHealth"])
        if condition == nil { notes.append("IOPowerSources battery health condition is unavailable.") }

        // Reader forwards only these allowlisted numeric fields from the BatteryData container.
        let batteryData = registry["BatteryData"] as? [String: Any] ?? [:]
        let design = capacity(registry["DesignCapacity"]) ?? capacity(batteryData["DesignCapacity"])
        var maximum = capacity(registry["AppleRawMaxCapacity"])
        if maximum == nil, let full = capacity(batteryData["FullChargeCapacity"]) {
            maximum = full
            notes.append("Maximum capacity uses caller-sanitized BatteryData.FullChargeCapacity, assumed mAh.")
        }
        if maximum == nil, let legacy = capacity(registry["MaxCapacity"]), legacy > 100,
           let design, design >= 1000, Double(legacy) <= Double(design) * 2 {
            maximum = legacy
            notes.append("Maximum capacity uses legacy MaxCapacity, inferred to be mAh from its range and DesignCapacity.")
        } else if maximum == nil, registry["MaxCapacity"] != nil {
            notes.append("MaxCapacity was not used as mAh because its units are ambiguous or it may be a percentage.")
        }
        if maximum == nil { notes.append("Maximum capacity in mAh is unavailable; AppleRawMaxCapacity is preferred over percentage-valued MaxCapacity.") }
        if design == nil { notes.append("Design capacity in mAh is unavailable.") }
        var health: Double?
        if let maximum, let design, design > 0 {
            let estimate = Double(maximum) / Double(design) * 100
            if estimate <= 200 {
                health = estimate
                notes.append("Health percent is an mAh maximum/design-capacity estimate, not the macOS health rating; it can exceed 100%.")
            } else { notes.append("Capacity ratio was implausible; health estimate is unavailable.") }
        } else { notes.append("Health estimate requires a positive design capacity and a maximum capacity in the same mAh units.") }

        let cycles = integer(registry["CycleCount"]).flatMap { (0...100_000).contains($0) ? $0 : nil }
        if cycles == nil { notes.append("CycleCount is missing or outside the accepted range 0...100000.") }
        let packData = registry["BatteryPackData"] as? [String: Any] ?? [:]
        var temperature: Double?
        var temperatureSource: String?
        // IOPSKeys.h explicitly defines Temperature in °C. Stats' open-source reader
        // documents the separate AppleSmartBatteryPack.BatteryData path as 0.01 °C.
        if let value = temperatureValue(source?["Temperature"], unit: .celsius) {
            temperature = value
            temperatureSource = "IOPowerSources.Temperature"
            notes.append("Temperature uses IOPowerSources.Temperature in °C, as defined by IOPSKeys.h.")
        } else if let value = temperatureValue(packData["Temperature"], unit: .centiCelsius) {
            temperature = value
            temperatureSource = "AppleSmartBatteryPack.BatteryData.Temperature"
            notes.append("Temperature uses AppleSmartBatteryPack.BatteryData.Temperature / 100 (0.01 °C), matching the open-source Stats reader; this registry convention is not a public API guarantee.")
        } else if let unit = registryTemperatureUnit, let value = temperatureValue(registry["Temperature"], unit: unit) {
            temperature = value
            temperatureSource = "AppleSmartBattery.Temperature"
            notes.append("Temperature uses AppleSmartBattery.Temperature with caller-specified units; units are never guessed from its numeric range.")
        }
        if temperature == nil { notes.append("Temperature is missing, has ambiguous units, or is outside -20...100 °C. VirtualTemperature is not substituted without verified source units.") }
        let voltageMV = validVoltage(registry["Voltage"]) ?? validVoltage(source?["Voltage"])
        if voltageMV == nil { notes.append("Voltage is missing or outside the accepted range 0...30000 mV.") }
        let current = amperage(registry["Amperage"], encoding: amperageEncoding) ?? amperage(source?["Current"], encoding: .signedMilliAmps)
        if current == nil { notes.append("Amperage is missing, ambiguous, invalid, or outside ±30000 mA; unsigned two's-complement requires an explicit encoding, never an inferred bit width.") }
        var watts: Double?
        if let voltageMV, let current {
            watts = voltageMV * current / 1_000_000
            notes.append("Power is the signed battery-side estimate Voltage[mV] × Amperage[mA] / 1e6 W; Amperage may be averaged and the values are not atomic. It is not wall-adapter or total system power.")
        } else { notes.append("Battery-side instantaneous power requires both voltage and amperage.") }
        return BatterySnapshot(
            timestamp: date, isPresent: true, percentage: percentage, powerSource: power,
            isCharging: charging, isCharged: charged, condition: condition,
            maximumCapacityMAh: maximum, designCapacityMAh: design, healthPercent: health,
            cycleCount: cycles, temperatureCelsius: temperature, voltageVolts: voltageMV.map { $0 / 1000 },
            amperageMA: current, powerWatts: watts, limitations: notes,
            availability: availability, readErrors: readErrors, temperatureSource: temperatureSource
        )
    }

    private static func numericObject(_ value: Any?) -> NSNumber? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
        return value
    }
    private static func number(_ value: Any?) -> Double? {
        guard let value = numericObject(value)?.doubleValue, value.isFinite else { return nil }
        return value
    }
    private static func integer(_ value: Any?) -> Int? {
        number(value).flatMap { Int(exactly: $0) }
    }
    private static func capacity(_ value: Any?) -> Int? {
        integer(value).flatMap { (0...100_000).contains($0) ? $0 : nil }
    }
    private static func boolean(_ value: Any?) -> Bool? {
        guard let value = value as? NSNumber else { return nil }
        if CFGetTypeID(value) == CFBooleanGetTypeID() { return value.boolValue }
        if value == 0 { return false }
        if value == 1 { return true }
        return nil
    }
    private static func nonemptyString(_ value: Any?) -> String? {
        guard let value = value as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }
    private static func temperatureValue(_ value: Any?, unit: BatteryTemperatureUnit) -> Double? {
        guard let raw = number(value) else { return nil }
        let celsius: Double
        switch unit {
        case .celsius: celsius = raw
        case .centiCelsius: celsius = raw / 100
        case .deciKelvin: celsius = raw / 10 - 273.15
        }
        return (-20...100).contains(celsius) ? celsius : nil
    }
    private static func validVoltage(_ value: Any?) -> Double? {
        number(value).flatMap { (0...30_000).contains($0) ? $0 : nil }
    }
    private static func amperage(_ value: Any?, encoding: BatteryAmperageEncoding) -> Double? {
        guard let object = numericObject(value) else { return nil }
        let direct = object.doubleValue
        guard direct.isFinite, direct.rounded() == direct else { return nil }
        if case .signedMilliAmps = encoding { return abs(direct) <= 30_000 ? direct : nil }
        // Parse decimal text rather than converting a rounded Double to UInt64, which can trap at 2^64.
        guard let unsigned = UInt64(object.stringValue) else { return nil }
        let signed: Int64
        switch encoding {
        case .signedMilliAmps: return nil
        case .unsignedTwosComplement16:
            guard let raw = UInt16(exactly: unsigned) else { return nil }
            signed = Int64(Int16(bitPattern: raw))
        case .unsignedTwosComplement32:
            guard let raw = UInt32(exactly: unsigned) else { return nil }
            signed = Int64(Int32(bitPattern: raw))
        case .unsignedTwosComplement64: signed = Int64(bitPattern: unsigned)
        }
        return abs(Double(signed)) <= 30_000 ? Double(signed) : nil
    }
}
