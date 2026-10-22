import Foundation

public enum DeviceReadStatus: String, Codable, Sendable {
    case available, noDevice, requiresUnlockAndTrust, unavailable, timedOut
}

public enum DeviceKind: String, Codable, Sendable {
    case iPhone, iPad
}

public enum DeviceChargingState: String, Codable, Sendable {
    case charging, full, notCharging
}

/// No persistent identifiers or user-assigned device names are collected.
public struct ConnectedDeviceSnapshot: Codable, Sendable, Equatable, Identifiable {
    /// An ordinal within this sample, not a UDID and not stable between samples.
    public let id: String
    public let productType: String?
    public let productVersion: String?
    public let kind: DeviceKind
    public let batteryPercentage: Int?
    public let chargingState: DeviceChargingState?
    public let externalPowerConnected: Bool?
    /// Reserved for a source with verified units. Standard lockdown battery values do not supply these.
    public let temperatureCelsius: Double?
    public let cycleCount: Int?
    public let designCapacityMAh: Int?
    public let fullChargeCapacityMAh: Int?
    /// "available" / "partial" / "failed" when the diagnostics query was attempted; nil when not attempted.
    public let batteryDetailsStatus: String?
    /// Short human-readable source path, e.g. "diagnostics_relay IORegistry AppleSmartBattery". Nil when not attempted.
    public let batteryDetailsSource: String?
    public let message: String?

    public init(id: String, productType: String? = nil, productVersion: String? = nil,
                kind: DeviceKind, batteryPercentage: Int? = nil,
                chargingState: DeviceChargingState? = nil, externalPowerConnected: Bool? = nil,
                temperatureCelsius: Double? = nil, cycleCount: Int? = nil,
                designCapacityMAh: Int? = nil, fullChargeCapacityMAh: Int? = nil,
                batteryDetailsStatus: String? = nil, batteryDetailsSource: String? = nil, message: String? = nil) {
        self.id = id
        self.productType = productType
        self.productVersion = productVersion
        self.kind = kind
        self.batteryPercentage = batteryPercentage
        self.chargingState = chargingState
        self.externalPowerConnected = externalPowerConnected
        self.temperatureCelsius = temperatureCelsius
        self.cycleCount = cycleCount
        self.designCapacityMAh = designCapacityMAh
        self.fullChargeCapacityMAh = fullChargeCapacityMAh
        self.batteryDetailsStatus = batteryDetailsStatus
        self.batteryDetailsSource = batteryDetailsSource
        self.message = message
    }
}

public struct DeviceSnapshot: Codable, Sendable, Equatable {
    public let capturedAt: Date
    public let status: DeviceReadStatus
    public let devices: [ConnectedDeviceSnapshot]
    /// True only after dlopen succeeds, even if required symbols are unavailable.
    public let frameworkLoaded: Bool
    public let message: String

    public init(capturedAt: Date = Date(), status: DeviceReadStatus,
                devices: [ConnectedDeviceSnapshot] = [], frameworkLoaded: Bool = false, message: String) {
        self.capturedAt = capturedAt
        self.status = status
        self.devices = devices
        self.frameworkLoaded = frameworkLoaded
        self.message = message
    }
}
