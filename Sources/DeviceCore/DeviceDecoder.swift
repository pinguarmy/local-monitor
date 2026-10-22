import Foundation
import CoreFoundation

/// Outcome of the optional diagnostics_relay battery pack query. Values are raw on-device
/// numbers from the explicit Diagnostics.IORegistry.BatteryData path of the
/// AppleSmartBatteryPack entry; unit conversion and validation live in DeviceDecoder.
enum BatteryDiagnostics {
    case notAttempted
    case failed
    case values([String: NSNumber])

    /// Short human-readable source path. Never a URL, never device-specific.
    static let sourceName = "diagnostics_relay IORegistry AppleSmartBatteryPack.BatteryData"
}

/// Parses only the allowlisted lockdown product and battery keys, plus the whitelisted
/// AppleSmartBatteryPack BatteryData scalars. Fixtures may contain extra keys; they are
/// never copied into snapshots.
///
/// Source-specific unit mapping corroborated by publicly documented diagnostics
/// and open-source readers listed in docs/DATA_SOURCES.md:
///   - BatteryData.Temperature is centi-degrees Celsius.
///   - BatteryData.AppleRawMaxCapacity is the current full charge capacity in mAh,
///     with NominalChargeCapacity (gauge-learned) as the documented fallback.
///   - BatteryData.DesignCapacity is the nameplate capacity in mAh.
///   - BatteryData.CycleCount is a plain integer.
/// VirtualTemperature is extracted but never mapped: its reference point is not the
/// physical cell and must not be mixed into temperatureCelsius.
/// The AppleSmartBattery class entry's top-level MaxCapacity/FullChargeCapacity are
/// percentages on iOS and are never accepted as mAh; only the nested BatteryData path
/// above is read, so they cannot be picked up even by name.
enum DeviceDecoder {
    /// Sanity bounds for pack metrics. Temperature is accepted only inside -20...100°C
    /// after the source-specific centi-C conversion. Design capacity must be a plausible
    /// nameplate mAh; full charge capacity may decay to 0 on a worn pack and is shown
    /// independently of design.
    static let centiCelsiusRange = -2_000...10_000
    static let designCapacityMAhRange = 500...30_000
    static let fullChargeCapacityMAhRange = 0...60_000

    static func decode(product: [String: Any], battery: [String: Any],
                       diagnostics: BatteryDiagnostics = .notAttempted, ordinal: Int) -> ConnectedDeviceSnapshot? {
        let type = safeString(product["ProductType"], pattern: "^(iPhone|iPad)[0-9]+,[0-9]+$")
        let deviceClass = product["DeviceClass"] as? String
        let kind: DeviceKind
        if type?.hasPrefix("iPhone") == true || deviceClass == "iPhone" { kind = .iPhone }
        else if type?.hasPrefix("iPad") == true || deviceClass == "iPad" { kind = .iPad }
        else { return nil }
        let charging = boolean(battery["BatteryIsCharging"])
        let full = boolean(battery["FullyCharged"])
        let state: DeviceChargingState? = full == true ? .full : (charging.map { $0 ? .charging : .notCharging })
        let percentage = integer(battery["BatteryCurrentCapacity"], range: 0...100)
        var cycles: Int?
        var temperature: Double?
        var designMAh: Int?
        var fullChargeMAh: Int?
        var detailsStatus: String?
        var detailsSource: String?
        switch diagnostics {
        case .notAttempted:
            break
        case .failed:
            detailsStatus = "failed"
            detailsSource = BatteryDiagnostics.sourceName
        case .values(let values):
            detailsSource = BatteryDiagnostics.sourceName
            cycles = integer(values["CycleCount"], range: 0...100_000)
            // Source-specific centi-C; VirtualTemperature is deliberately not a fallback.
            temperature = centiCelsius(values["Temperature"])
            // Full charge capacity: raw max first, nominal (gauge-learned) as the
            // documented fallback. Design capacity is the nameplate reference and is
            // shown independently — a missing or invalid full value never hides it.
            let design = integer(values["DesignCapacity"], range: designCapacityMAhRange)
            let rawMax = integer(values["AppleRawMaxCapacity"], range: fullChargeCapacityMAhRange)
            let nominal = integer(values["NominalChargeCapacity"], range: fullChargeCapacityMAhRange)
            var fullCandidate = rawMax ?? nominal
            if let full = fullCandidate {
                if let design {
                    // A worn pack can sit far below design; only absurd inflation
                    // (over twice the nameplate) marks the value as untrustworthy.
                    if full > design * 2 { fullCandidate = nil }
                } else if full < 500 {
                    // Without a design reference, percentage-scale lookalikes (e.g. 100)
                    // are rejected; a real nested mAh reading is trusted as-is.
                    fullCandidate = nil
                }
            }
            designMAh = design
            fullChargeMAh = fullCandidate
            let anyValue = cycles != nil || temperature != nil || designMAh != nil || fullChargeMAh != nil
            detailsStatus = (cycles != nil && temperature != nil && designMAh != nil && fullChargeMAh != nil)
                ? "available" : (anyValue ? "partial" : "failed")
        }
        let message: String
        switch detailsStatus {
        case "available":
            message = "温度、容量与循环次数来自设备电池组诊断只读查询。"
        case "partial":
            message = "电池组诊断只读查询仅返回部分指标；缺失项未显示。"
        case "failed":
            message = percentage == nil ? "设备未提供电池百分比；电池诊断读取失败。" : "电池诊断读取失败，仅显示基础电量。"
        default:
            message = percentage == nil ? "设备未提供电池百分比；温度、容量和循环次数在此只读接口中不可用。" : "温度、容量和循环次数在此只读接口中不可用。"
        }
        return ConnectedDeviceSnapshot(
            id: "device-\(ordinal)", productType: type,
            productVersion: safeString(product["ProductVersion"], pattern: "^[0-9]+(\\.[0-9]+){0,3}$"),
            kind: kind, batteryPercentage: percentage, chargingState: state,
            externalPowerConnected: boolean(battery["ExternalConnected"]),
            temperatureCelsius: temperature, cycleCount: cycles,
            designCapacityMAh: designMAh, fullChargeCapacityMAh: fullChargeMAh,
            batteryDetailsStatus: detailsStatus, batteryDetailsSource: detailsSource,
            message: message
        )
    }

    /// BatteryData.Temperature is centi-degrees Celsius on this source. Only the explicit
    /// source-specific scaling is applied; values outside the sanity band are rejected.
    private static func centiCelsius(_ value: Any?) -> Double? {
        guard let raw = integer(value, range: centiCelsiusRange) else { return nil }
        return Double(raw) / 100.0
    }

    private static func safeString(_ value: Any?, pattern: String) -> String? {
        guard let value = value as? String, value.utf8.count <= 40,
              value.range(of: pattern, options: .regularExpression) != nil else { return nil }
        return value
    }

    private static func integer(_ value: Any?, range: ClosedRange<Int>) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        guard double.isFinite, double.rounded() == double,
              double >= Double(range.lowerBound), double <= Double(range.upperBound) else { return nil }
        return Int(double)
    }

    private static func boolean(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }
}

/// Fixed categories, never raw framework errors containing device information.
enum DeviceNativeFailure {
    static func status(for code: Int32) -> DeviceReadStatus {
        let bits = UInt32(bitPattern: code)
        if bits == 0xe800000c || bits == 0xe8000024 { return .timedOut }
        let lockedOrUntrusted: Set<UInt32> = [0xe8000016, 0xe800001a, 0xe800001b,
            0xe800001c, 0xe8000025, 0xe800005c, 0xe8000081, 0xe8000095, 0xe8000096]
        return lockedOrUntrusted.contains(bits) ? .requiresUnlockAndTrust : .unavailable
    }
}
