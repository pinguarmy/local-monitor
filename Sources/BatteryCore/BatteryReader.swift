import Foundation
import IOKit
import IOKit.ps

/// Reads public power-source APIs and fixed allowlists of read-only registry properties.
/// Does not invoke shell commands, SMC, network requests, or charging controls.
public struct BatteryReader: Sendable {
    public init() {}

    public func read() -> BatterySnapshot {
        let sources = Self.powerSources()
        let registry = Self.registry()
        #if arch(x86_64)
        // Apple's open-source Intel driver publishes the original SBS decikelvin value.
        let unit: BatteryTemperatureUnit? = .deciKelvin
        #else
        // Do not assign Intel SBS units to an undocumented Apple Silicon top-level value.
        let unit: BatteryTemperatureUnit? = nil
        #endif
        return BatteryDecoder.decode(
            powerSources: sources.values, registry: registry.values, date: Date(),
            readErrors: sources.errors + registry.errors, registryTemperatureUnit: unit
        )
    }

    private static func powerSources() -> (values: [[String: Any]], errors: [BatteryReadError]) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return ([], [.powerSourcesUnavailable])
        }
        let keys = [
            "Type", "Transport Type", "Is Present", "Current Capacity", "Max Capacity",
            "Power Source State", "Is Charging", "Is Charged", "BatteryHealthCondition", "BatteryHealth",
            "Temperature", "Voltage", "Current"
        ]
        var values: [[String: Any]] = []
        var errors: [BatteryReadError] = []
        for item in list {
            guard let source = IOPSGetPowerSourceDescription(info, item)?.takeUnretainedValue() as? [String: Any] else {
                if !errors.contains(.powerSourceDescriptionUnavailable) { errors.append(.powerSourceDescriptionUnavailable) }
                continue
            }
            guard (source["Type"] as? String) == "InternalBattery" || (source["Transport Type"] as? String) == "Internal" else { continue }
            var result: [String: Any] = [:]
            for key in keys { result[key] = source[key] }
            values.append(result)
        }
        return (values, errors)
    }

    private static func registry() -> (values: [String: Any], errors: [BatteryReadError]) {
        var values: [String: Any] = [:]
        var errors: [BatteryReadError] = []
        var iterator: io_iterator_t = 0
        let status = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"), &iterator)
        if status != KERN_SUCCESS {
            errors.append(.registryUnavailable)
        } else {
            defer { IOObjectRelease(iterator) }
            let service = IOIteratorNext(iterator)
            if service != IO_OBJECT_NULL {
                defer { IOObjectRelease(service) }
                for key in ["BatteryInstalled", "DesignCapacity", "AppleRawMaxCapacity", "MaxCapacity", "CycleCount", "Temperature", "VirtualTemperature", "Voltage", "Amperage"] {
                    values[key] = property(service, key)
                }
                let data = numericBatteryData(service, keys: ["FullChargeCapacity", "DesignCapacity"])
                if !data.isEmpty { values["BatteryData"] = data }
                // Missing optional temperature is not an error. A matched service with no
                // readable allowlisted properties is unavailable, not evidence of no battery.
                if values.isEmpty { errors.append(.registryUnavailable) }
            }
        }

        // Newer macOS versions expose temperature on this separate service. Match its
        // fixed name, read only BatteryData, and immediately discard everything but Temperature.
        // Reference: https://github.com/exelban/stats/blob/master/Modules/Battery/readers.swift
        let pack = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceNameMatching("AppleSmartBatteryPack"))
        if pack != IO_OBJECT_NULL {
            defer { IOObjectRelease(pack) }
            let data = numericBatteryData(pack, keys: ["Temperature"])
            if !data.isEmpty { values["BatteryPackData"] = data }
        }
        return (values, errors)
    }

    private static func property(_ service: io_registry_entry_t, _ key: String) -> CFTypeRef? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    private static func numericBatteryData(_ service: io_registry_entry_t, keys: [String]) -> [String: Any] {
        // IOKit cannot fetch a nested field independently. Never enumerate, log, persist,
        // or forward the container; copy only numeric fields from the explicit allowlist.
        guard let data = property(service, "BatteryData") as? [String: Any] else { return [:] }
        var result: [String: Any] = [:]
        for key in keys {
            if let number = data[key] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() { result[key] = number }
        }
        return result
    }
}
