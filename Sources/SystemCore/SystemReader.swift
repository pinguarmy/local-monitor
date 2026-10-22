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
        var limitations = [
            "CPU 使用率来自两次 Mach tick 差值；1/5/15 分钟负载不是百分比。",
            "内存 used = max(匿名常驻页 - 可清除页, 0) + wired + compressor；available = 总内存 - used，是可回收估算。pressure 单独读取内核状态，不用内存占比推算。",
            "根文件系统容量来自 statfs(/)，APFS 卷共享空间；不扫描目录，不计算文件大小。",
            "网络只累计已启用的 enN 物理接口，按接口索引去重；排除 lo、VPN、bridge、AWDL 等叠加接口，不等同于互联网计费流量。"
        ]

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
        if ticks == nil { limitations.append("Mach CPU tick 读取失败，CPU 使用率不可用。") }
        else if usage == nil { limitations.append("CPU 使用率需要两次有效采样；新建、恢复或计数重置后的首采样不显示百分比。") }

        let gpuUtilization = Self.readGPUUtilization()
        let gpu: GPUStats? = gpuName != nil || gpuUtilization != nil ? GPUStats(name: gpuName, utilizationPercent: gpuUtilization) : nil
        if gpuUtilization == nil { limitations.append("GPU 未暴露白名单 IOAccelerator PerformanceStatistics 百分比，利用率不可用；不使用 sudo、powermetrics 或 SMC。") }
        else { limitations.append("GPU 利用率读取 IOAccelerator PerformanceStatistics 已知百分比键，驱动未公开该计数的采样时间窗口。") }

        let memory = Self.readMemory(host: host)
        if memory == nil { limitations.append("Mach 内存统计读取失败，内存指标不可用。") }
        else {
            if memory?.swapUsedBytes == nil { limitations.append("vm.swapusage 读取失败，swap 用量不可用。") }
            if memory?.pressure == .unknown { limitations.append("内核未提供可识别的 memory_pressure，内存压力未知。") }
        }
        let disk = Self.readDisk()
        if disk == nil { limitations.append("根文件系统 statfs 读取失败，磁盘容量不可用。") }

        var network: NetworkStats?
        if let interfaces = Self.readNetworkInterfaces() {
            network = SystemMetrics.network(interfaces: interfaces, uptime: uptime, previous: previousNetwork)
            previousNetwork = NetworkBaseline(uptime: uptime, interfaces: interfaces)
            if network?.intervalSeconds == nil { limitations.append("网络速率需要同一组接口的两次有效采样；接口变化或计数重置时重新建立基线。") }
        } else {
            previousNetwork = nil
            limitations.append("网络接口计数读取失败，流量与速率不可用。")
        }
        return SystemSnapshot(timestamp: timestamp, cpu: cpu, gpu: gpu, memory: memory, disk: disk, network: network,
                              thermalState: Self.thermalState(process.thermalState), isLowPowerModeEnabled: process.isLowPowerModeEnabled,
                              uptimeSeconds: uptime, limitations: limitations)
    }

    private static func readCPUTicks(host: host_t) -> CPUTicks? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count) }
        }
        guard result == KERN_SUCCESS else { return nil }
        return CPUTicks(user: info.cpu_ticks.0, system: info.cpu_ticks.1, idle: info.cpu_ticks.2, nice: info.cpu_ticks.3)
    }

    private static func readMemory(host: host_t) -> MemoryStats? {
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

    private static func sysctlInt32(_ name: String) -> Int32? {
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
