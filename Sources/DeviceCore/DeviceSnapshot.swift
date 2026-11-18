import Foundation

public enum DeviceReadStatus: String, Codable, Sendable {
    case available, noDevice, requiresUnlockAndTrust, unavailable, timedOut
}

/// Machine-readable reason a read was unavailable. A stable contract for UI localization:
/// raw values are part of the JSON output and must not be renamed.
/// Nil for available / noDevice / requiresUnlockAndTrust results and for plain timeouts.
public enum DeviceReadIssue: String, Codable, Sendable {
    case frameworkUnavailable        // MobileDevice framework or required symbols missing
    case subscriptionFailed          // could not subscribe to device notifications
    case notificationCleanupFailed   // could not unsubscribe; the reader is quarantined until app restart
    case readInProgress              // a previous read has not finished yet
    case deviceUnreadable            // a device was found but could not be read (not a lock/trust problem)
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
    /// Battery pack temperature from the diagnostics_relay BatteryData query (source unit is
    /// centi-degrees Celsius, converted and range-checked by DeviceDecoder). Nil when the
    /// diagnostics query was not attempted, failed, or returned no valid value.
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
    /// Short English explanation for logs and the CLI. Not localized; UIs should use `status` and `issue`.
    public let message: String
    /// Why the read was unavailable, when there is a specific machine-readable reason.
    /// Optional for JSON backward compatibility: a missing key decodes as nil and nil is not encoded.
    public let issue: DeviceReadIssue?

    public init(capturedAt: Date = Date(), status: DeviceReadStatus,
                devices: [ConnectedDeviceSnapshot] = [], frameworkLoaded: Bool = false, message: String,
                issue: DeviceReadIssue? = nil) {
        self.capturedAt = capturedAt
        self.status = status
        self.devices = devices
        self.frameworkLoaded = frameworkLoaded
        self.message = message
        self.issue = issue
    }
}
