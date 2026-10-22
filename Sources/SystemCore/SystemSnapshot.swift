import Foundation

/// A read-only, JSON-friendly sample. Missing measurements remain nil, never a fabricated zero.
public struct SystemSnapshot: Codable, Sendable {
    public let timestamp: Date
    public let cpu: CPUStats?
    public let gpu: GPUStats?
    public let memory: MemoryStats?
    public let disk: DiskStats?
    public let network: NetworkStats?
    public let thermalState: ThermalState
    public let isLowPowerModeEnabled: Bool
    public let uptimeSeconds: Double
    public let limitations: [String]

    public init(timestamp: Date, cpu: CPUStats?, gpu: GPUStats?, memory: MemoryStats?, disk: DiskStats?, network: NetworkStats?, thermalState: ThermalState, isLowPowerModeEnabled: Bool, uptimeSeconds: Double, limitations: [String]) {
        self.timestamp = timestamp
        self.cpu = cpu
        self.gpu = gpu
        self.memory = memory
        self.disk = disk
        self.network = network
        self.thermalState = thermalState
        self.isLowPowerModeEnabled = isLowPowerModeEnabled
        self.uptimeSeconds = uptimeSeconds
        self.limitations = limitations
    }
}

public struct CPUStats: Codable, Sendable {
    public let logicalCoreCount: Int
    public let physicalCoreCount: Int?
    /// Aggregate busy tick delta / total tick delta, in 0...100, not a load average.
    /// Nil until there are two valid samples after creation or resetBaselines().
    public let usagePercent: Double?
    /// Runnable / uninterruptible task counts. These are not utilization percentages.
    public let loadAverage1: Double?
    public let loadAverage5: Double?
    public let loadAverage15: Double?

    public init(logicalCoreCount: Int, physicalCoreCount: Int?, usagePercent: Double?, loadAverage1: Double?, loadAverage5: Double?, loadAverage15: Double?) {
        self.logicalCoreCount = logicalCoreCount
        self.physicalCoreCount = physicalCoreCount
        self.usagePercent = usagePercent
        self.loadAverage1 = loadAverage1
        self.loadAverage5 = loadAverage5
        self.loadAverage15 = loadAverage15
    }
}

public struct GPUStats: Codable, Sendable {
    /// Metal device display name only. No device identifier is read.
    public let name: String?
    /// A recognized IOAccelerator PerformanceStatistics percentage, or nil if not exposed.
    public let utilizationPercent: Double?

    public init(name: String?, utilizationPercent: Double?) {
        self.name = name
        self.utilizationPercent = utilizationPercent
    }
}

public enum MemoryPressure: String, Codable, Sendable {
    case normal, warning, critical, unknown
}

public struct MemoryStats: Codable, Sendable {
    public let totalBytes: UInt64
    /// Estimated app resident + wired + compressed memory, capped at physical RAM.
    /// app resident pages = max(internal_page_count - purgeable_count, 0).
    public let usedBytes: UInt64
    /// totalBytes - usedBytes. A reclaimable estimate, not a promise that allocation will succeed.
    public let availableBytes: UInt64
    /// Physical bytes occupied by the compressor, not uncompressed logical size.
    public let compressedBytes: UInt64
    public let swapUsedBytes: UInt64?
    /// Raw kernel memory-pressure level, not a ratio derived from used RAM.
    public let pressure: MemoryPressure

    public init(totalBytes: UInt64, usedBytes: UInt64, availableBytes: UInt64, compressedBytes: UInt64, swapUsedBytes: UInt64?, pressure: MemoryPressure) {
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.availableBytes = availableBytes
        self.compressedBytes = compressedBytes
        self.swapUsedBytes = swapUsedBytes
        self.pressure = pressure
    }
}

public struct DiskStats: Codable, Sendable {
    /// statfs("/") filesystem capacity. APFS volumes may share this capacity.
    public let totalBytes: UInt64
    /// All free blocks, including blocks reserved by the filesystem.
    public let freeBytes: UInt64
    /// Blocks available to unprivileged callers, excluding reserved blocks.
    public let availableBytes: UInt64

    public init(totalBytes: UInt64, freeBytes: UInt64, availableBytes: UInt64) {
        self.totalBytes = totalBytes
        self.freeBytes = freeBytes
        self.availableBytes = availableBytes
    }
}

public struct NetworkStats: Codable, Sendable {
    /// Cumulative counters from eligible active physical interfaces, not Internet billing totals.
    public let receivedBytes: UInt64
    public let sentBytes: UInt64
    /// Nil without a previous sample of the same interfaces and nondecreasing counters.
    public let downloadBytesPerSecond: Double?
    public let uploadBytesPerSecond: Double?
    public let intervalSeconds: Double?

    public init(receivedBytes: UInt64, sentBytes: UInt64, downloadBytesPerSecond: Double?, uploadBytesPerSecond: Double?, intervalSeconds: Double?) {
        self.receivedBytes = receivedBytes
        self.sentBytes = sentBytes
        self.downloadBytesPerSecond = downloadBytesPerSecond
        self.uploadBytesPerSecond = uploadBytesPerSecond
        self.intervalSeconds = intervalSeconds
    }
}

public enum ThermalState: String, Codable, Sendable {
    case nominal, fair, serious, critical, unknown
}
