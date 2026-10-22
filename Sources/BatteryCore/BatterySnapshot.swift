import Foundation

/// Presence is independent of read errors: a present battery can have a partially failed sample.
public enum BatteryAvailability: String, Codable, Sendable {
    case present, absent, unknown
}

/// Fixed error codes only. Never carries registry contents or hardware identifiers.
public enum BatteryReadError: String, Codable, Sendable {
    case powerSourcesUnavailable
    case powerSourceDescriptionUnavailable
    case registryUnavailable
}

/// One read-only sample. Optional measurements are absent when their units or values cannot be trusted.
public struct BatterySnapshot: Codable, Sendable, Equatable {
    public let timestamp: Date
    /// Compatibility flag. False means absent OR unknown; new clients should use availability.
    public let isPresent: Bool
    public let availability: BatteryAvailability
    public let readErrors: [BatteryReadError]
    public let percentage: Int?
    /// IOPowerSources values: "AC Power", "Battery Power", "Off Line", or "Unknown".
    public let powerSource: String
    public let isCharging: Bool?
    public let isCharged: Bool?
    public let condition: String?
    public let maximumCapacityMAh: Int?
    public let designCapacityMAh: Int?
    public let healthPercent: Double?
    /// Reserved for a verified OS-reported percentage, never filled from the mAh estimate.
    public let reportedHealthPercent: Double?
    public let cycleCount: Int?
    public let temperatureCelsius: Double?
    /// A fixed allowlisted property path, not a device name or identifier.
    public let temperatureSource: String?
    public let voltageVolts: Double?
    public let amperageMA: Double?
    /// Signed battery-side estimate, not wall-adapter or whole-system consumption.
    public let powerWatts: Double?
    public let limitations: [String]

    public init(
        timestamp: Date = Date(), isPresent: Bool, percentage: Int? = nil,
        powerSource: String = "Unknown", isCharging: Bool? = nil, isCharged: Bool? = nil,
        condition: String? = nil, maximumCapacityMAh: Int? = nil, designCapacityMAh: Int? = nil,
        healthPercent: Double? = nil, cycleCount: Int? = nil, temperatureCelsius: Double? = nil,
        voltageVolts: Double? = nil, amperageMA: Double? = nil, powerWatts: Double? = nil,
        limitations: [String] = [], availability: BatteryAvailability? = nil,
        readErrors: [BatteryReadError] = [], temperatureSource: String? = nil,
        reportedHealthPercent: Double? = nil
    ) {
        self.timestamp = timestamp
        self.availability = availability ?? (isPresent ? .present : (readErrors.isEmpty ? .absent : .unknown))
        self.isPresent = self.availability == .present
        self.readErrors = readErrors
        self.percentage = percentage
        self.powerSource = powerSource
        self.isCharging = isCharging
        self.isCharged = isCharged
        self.condition = condition
        self.maximumCapacityMAh = maximumCapacityMAh
        self.designCapacityMAh = designCapacityMAh
        self.healthPercent = healthPercent
        self.reportedHealthPercent = reportedHealthPercent
        self.cycleCount = cycleCount
        self.temperatureCelsius = temperatureCelsius
        self.temperatureSource = temperatureSource
        self.voltageVolts = voltageVolts
        self.amperageMA = amperageMA
        self.powerWatts = powerWatts
        self.limitations = limitations
    }

    private enum CodingKeys: String, CodingKey {
        case timestamp, isPresent, availability, readErrors, percentage, powerSource, isCharging, isCharged
        case condition, maximumCapacityMAh, designCapacityMAh, healthPercent, reportedHealthPercent
        case cycleCount, temperatureCelsius, temperatureSource, voltageVolts, amperageMA, powerWatts, limitations
    }

    /// Old snapshots lack the new fields. Their false presence flag cannot establish absence reliably.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let oldPresence = try values.decode(Bool.self, forKey: .isPresent)
        self.init(
            timestamp: try values.decode(Date.self, forKey: .timestamp), isPresent: oldPresence,
            percentage: try values.decodeIfPresent(Int.self, forKey: .percentage),
            powerSource: try values.decode(String.self, forKey: .powerSource),
            isCharging: try values.decodeIfPresent(Bool.self, forKey: .isCharging),
            isCharged: try values.decodeIfPresent(Bool.self, forKey: .isCharged),
            condition: try values.decodeIfPresent(String.self, forKey: .condition),
            maximumCapacityMAh: try values.decodeIfPresent(Int.self, forKey: .maximumCapacityMAh),
            designCapacityMAh: try values.decodeIfPresent(Int.self, forKey: .designCapacityMAh),
            healthPercent: try values.decodeIfPresent(Double.self, forKey: .healthPercent),
            cycleCount: try values.decodeIfPresent(Int.self, forKey: .cycleCount),
            temperatureCelsius: try values.decodeIfPresent(Double.self, forKey: .temperatureCelsius),
            voltageVolts: try values.decodeIfPresent(Double.self, forKey: .voltageVolts),
            amperageMA: try values.decodeIfPresent(Double.self, forKey: .amperageMA),
            powerWatts: try values.decodeIfPresent(Double.self, forKey: .powerWatts),
            limitations: try values.decodeIfPresent([String].self, forKey: .limitations) ?? [],
            availability: try values.decodeIfPresent(BatteryAvailability.self, forKey: .availability) ?? (oldPresence ? .present : .unknown),
            readErrors: try values.decodeIfPresent([BatteryReadError].self, forKey: .readErrors) ?? [],
            temperatureSource: try values.decodeIfPresent(String.self, forKey: .temperatureSource),
            reportedHealthPercent: try values.decodeIfPresent(Double.self, forKey: .reportedHealthPercent)
        )
    }
}
