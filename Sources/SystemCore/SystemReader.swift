import Foundation
import Darwin
import IOKit
import Metal

/// A synchronous, read-only collector. Own one instance on the parent's serial sampling queue.
/// There is no timer, background work, process enumeration, shell command or hardware write.
/// The class is deliberately not Sendable: read/reset must not be called concurrently.
public final class SystemReader {
    private var previousCPU: CPUTicks?
    private var previousNetwork: NetworkBaseline?
    private let logicalCoreCount: Int
    private let physicalCoreCount: Int?
    private let gpuName: String?
    /// Method notes that apply to every sample. Built once, not on every read.
    private static let baseLimitations: [String] = [
        "CPU usage is the busy share of the Mach tick delta between two samples; the 1/5/15-minute load averages are not percentages.",
        "Memory used = max(anonymous resident pages - purgeable pages, 0) + wired + compressor pages; available = total - used, a reclaimable estimate. Pressure is read separately from the kernel, not derived from the used ratio.",
        "Disk capacity comes from statfs(\"/\"); APFS volumes share space. No directories are scanned and no file sizes are computed.",
        "Network totals count only active physical enN interfaces, deduplicated by interface index; loopback, VPN, bridge, AWDL and other overlay interfaces are excluded. They are not internet billing totals."
    ]

    public init() {
        logicalCoreCount = max(1, Int(Self.sysctlInt32("hw.logicalcpu") ?? Int32(ProcessInfo.processInfo.processorCount)))
        physicalCoreCount = Self.sysctlInt32("hw.physicalcpu").flatMap { $0 > 0 ? Int($0) : nil }
        gpuName = MTLCreateSystemDefaultDevice()?.name
    }

    /// Call when the panel closes, changes tab or sleeps, and before sampling resumes.
    /// The next CPU percentage and network rates will be nil until the following read.
    public func resetBaselines() {
        previousCPU = nil
        previousNetwork = nil
    }

    public func read() -> SystemSnapshot {
        let timestamp = Date()
        let process = ProcessInfo.processInfo
        let uptime = process.systemUptime
        var limitations = Self.baseLimitations

        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let ticks = Self.readCPUTicks(host: host)
        let usage = ticks?.utilization(since: previousCPU)
        previousCPU = ticks
        var averages = [Double](repeating: 0, count: 3)
        let loadCount = getloadavg(&averages, 3)
        let cpu = CPUStats(logicalCoreCount: logicalCoreCount, physicalCoreCount: physicalCoreCount, usagePercent: usage,
                           loadAverage1: loadCount >= 1 ? averages[0] : nil,
                           loadAverage5: loadCount >= 2 ? averages[1] : nil,
                           loadAverage15: loadCount >= 3 ? averages[2] : nil)
        if ticks == nil { limitations.append("Reading Mach CPU ticks failed; CPU usage is unavailable.") }
        else if usage == nil { limitations.append("CPU usage needs two valid samples; the first sample after creation, resetBaselines() or a counter reset has no percentage.") }

        let gpuUtilization = Self.readGPUUtilization()
        let gpu: GPUStats? = gpuName != nil || gpuUtilization != nil ? GPUStats(name: gpuName, utilizationPercent: gpuUtilization) : nil
        if gpuUtilization == nil { limitations.append("The GPU does not expose an allowlisted IOAccelerator PerformanceStatistics percentage, so utilization is unavailable; sudo, powermetrics and the SMC are not used.") }
        else { limitations.append("GPU utilization reads a known percentage key from IOAccelerator PerformanceStatistics; the driver does not document that counter's sampling window.") }

        let memory = Self.readMemory(host: host)
        if memory == nil { limitations.append("Reading Mach memory statistics failed; memory metrics are unavailable.") }
        else {
            if memory?.swapUsedBytes == nil { limitations.append("Reading vm.swapusage failed; swap usage is unavailable.") }
            if memory?.pressure == .unknown { limitations.append("The kernel did not report a recognized memory pressure level; memory pressure is unknown.") }
        }
        let disk = Self.readDisk()
        if disk == nil { limitations.append("statfs on the root filesystem failed; disk capacity is unavailable.") }

        var network: NetworkStats?
        if let interfaces = Self.readNetworkInterfaces() {
            network = SystemMetrics.network(interfaces: interfaces, uptime: uptime, previous: previousNetwork)
            previousNetwork = NetworkBaseline(uptime: uptime, interfaces: interfaces)
            if interfaces.isEmpty {
                // Without this, an offline Mac would be told forever that it needs a second sample.
                limitations.append("No active physical enN interface was found; network totals are 0 and rates are unavailable.")
            } else if network?.intervalSeconds == nil { limitations.append("Network rates need two valid samples of the same set of interfaces; the baseline is re-established when interfaces change or a counter resets.") }
        } else {
            previousNetwork = nil
            limitations.append("Reading network interface counters failed; traffic totals and rates are unavailable.")
        }
        return SystemSnapshot(timestamp: timestamp, cpu: cpu, gpu: gpu, memory: memory, disk: disk, network: network,
                              thermalState: Self.thermalState(process.thermalState), isLowPowerModeEnabled: process.isLowPowerModeEnabled,
                              uptimeSeconds: uptime, limitations: limitations)
    }

    /// Internal so `SystemLoadReader` shares the native read instead of duplicating it.
    static func readCPUTicks(host: host_t) -> CPUTicks? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count) }
        }
        guard result == KERN_SUCCESS else { return nil }
        return CPUTicks(user: info.cpu_ticks.0, system: info.cpu_ticks.1, idle: info.cpu_ticks.2, nice: info.cpu_ticks.3)
    }

    /// Internal so `SystemLoadReader` shares the native read instead of duplicating it.
    static func readMemory(host: host_t) -> MemoryStats? {
        var info = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(host, HOST_VM_INFO64, $0, &count) }
        }
        var pageSize: vm_size_t = 0
        guard result == KERN_SUCCESS, host_page_size(host, &pageSize) == KERN_SUCCESS, pageSize > 0 else { return nil }
        var total: UInt64 = 0
        var totalSize = MemoryLayout<UInt64>.size
        guard sysctlbyname("hw.memsize", &total, &totalSize, nil, 0) == 0, total > 0 else { return nil }
        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        let swapUsed = sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 ? swap.xsu_used : nil
        return SystemMetrics.memory(totalBytes: total, pageSize: UInt64(pageSize), internalPages: UInt64(info.internal_page_count),
                                    purgeablePages: UInt64(info.purgeable_count), wiredPages: UInt64(info.wire_count),
                                    compressorPages: UInt64(info.compressor_page_count), swapUsedBytes: swapUsed,
                                    pressure: SystemMetrics.pressure(raw: sysctlInt32("kern.memorystatus_vm_pressure_level")))
    }

    private static func readDisk() -> DiskStats? {
        var info = statfs()
        guard statfs("/", &info) == 0, info.f_bsize > 0 else { return nil }
        let block = UInt64(info.f_bsize)
        return DiskStats(totalBytes: SystemMetrics.saturatingMultiply(info.f_blocks, block),
                         freeBytes: SystemMetrics.saturatingMultiply(info.f_bfree, block),
                         availableBytes: SystemMetrics.saturatingMultiply(info.f_bavail, block))
    }

    private static func readNetworkInterfaces() -> [InterfaceCounters]? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return nil }
        defer { if let head { freeifaddrs(head) } }
        var indices = Set<UInt32>()
        var cursor = head
        while let node = cursor {
            let value = node.pointee
            if let name = value.ifa_name, let address = value.ifa_addr,
               SystemMetrics.isEligibleInterface(name: String(cString: name), flags: value.ifa_flags, family: address.pointee.sa_family) {
                let index = if_nametoindex(name)
                if index > 0 { indices.insert(index) }
            }
            cursor = value.ifa_next
        }
        guard !indices.isEmpty else { return [] }
        // getifaddrs's if_data contains 32-bit byte counters. Read routing IFINFO2's
        // 64-bit counters instead, without reading link-layer addresses or hardware IDs.
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var size = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0,
              size > 0, size <= 1_048_576 else { return nil }
        var bytes = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, u_int(mib.count), &bytes, &size, nil, 0) == 0, size <= bytes.count else { return nil }
        var interfaces: [UInt32: InterfaceCounters] = [:]
        let valid = bytes.withUnsafeBytes { buffer -> Bool in
            var offset = 0
            while offset + 4 <= size {
                let length = Int(buffer.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
                guard length >= 4, offset + length <= size else { return false }
                let type = buffer[offset + 3]
                if type == UInt8(RTM_IFINFO2), length >= MemoryLayout<if_msghdr2>.size {
                    let message = buffer.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    let index = UInt32(message.ifm_index)
                    if indices.contains(index) {
                        interfaces[index] = InterfaceCounters(index: index, received: message.ifm_data.ifi_ibytes, sent: message.ifm_data.ifi_obytes)
                    }
                }
                offset += length
            }
            return offset == size
        }
        guard valid, Set(interfaces.keys) == indices else { return nil }
        return interfaces.values.sorted { $0.index < $1.index }
    }

    private static func readGPUUtilization() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var values: [Double] = []
        var serviceCount = 0
        while case let service = IOIteratorNext(iterator), service != 0 {
            serviceCount += 1
            defer { IOObjectRelease(service) }
            // Read only this telemetry property, never copy or print the full registry.
            guard let property = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(),
                  let statistics = property as? [String: Any],
                  let utilization = SystemMetrics.gpuUtilization(statistics: statistics) else { continue }
            values.append(utilization)
        }
        // A single Metal name cannot be safely associated with multiple accelerators.
        return serviceCount == 1 && values.count == 1 ? values[0] : nil
    }

    static func sysctlInt32(_ name: String) -> Int32? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0, size == MemoryLayout<Int32>.size else { return nil }
        return value
    }

    private static func thermalState(_ state: ProcessInfo.ThermalState) -> ThermalState {
        switch state {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .unknown
        }
    }
}
