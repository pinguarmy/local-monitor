import Foundation
import Darwin

/// A small, JSON-free sample for the menu bar: CPU usage and memory used/total only.
/// Missing measurements remain nil, never a fabricated zero.
public struct SystemLoadSample: Sendable, Equatable {
    public let timestamp: Date
    /// Busy share of the Mach tick delta since the previous read, 0...100.
    /// Nil until there are two valid samples after creation or `resetBaseline()`.
    public let cpuUsagePercent: Double?
    /// Same definition as `MemoryStats.usedBytes`; nil when the Mach memory read failed.
    public let memoryUsedBytes: UInt64?
    public let memoryTotalBytes: UInt64?

    public init(timestamp: Date, cpuUsagePercent: Double?, memoryUsedBytes: UInt64?, memoryTotalBytes: UInt64?) {
        self.timestamp = timestamp
        self.cpuUsagePercent = cpuUsagePercent
        self.memoryUsedBytes = memoryUsedBytes
        self.memoryTotalBytes = memoryTotalBytes
    }

    /// Used / total in 0...100; nil when memory was not read or the total is zero.
    public var memoryUsedPercent: Double? {
        guard let used = memoryUsedBytes, let total = memoryTotalBytes, total > 0 else { return nil }
        return min(Double(used) / Double(total) * 100, 100)
    }
}

/// A deliberately light collector for menu bar sampling: one Mach CPU tick read and one Mach
/// memory read per call. It never touches the GPU registry, the disk or network interfaces.
/// Own one instance on a serial queue; the class is not Sendable and must not be called concurrently.
public final class SystemLoadReader {
    private var previousCPU: CPUTicks?

    public init() {}

    /// The next CPU percentage is nil until the following read.
    public func resetBaseline() {
        previousCPU = nil
    }

    public func read() -> SystemLoadSample {
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let ticks = SystemReader.readCPUTicks(host: host)
        let memory = SystemReader.readMemory(host: host)
        let sample = Self.sample(timestamp: Date(), ticks: ticks, previous: previousCPU, memory: memory)
        previousCPU = ticks
        return sample
    }

    /// Pure combination of the native reads, kept separate for deterministic tests.
    static func sample(timestamp: Date, ticks: CPUTicks?, previous: CPUTicks?, memory: MemoryStats?) -> SystemLoadSample {
        SystemLoadSample(timestamp: timestamp,
                         cpuUsagePercent: ticks?.utilization(since: previous),
                         memoryUsedBytes: memory?.usedBytes,
                         memoryTotalBytes: memory?.totalBytes)
    }
}
