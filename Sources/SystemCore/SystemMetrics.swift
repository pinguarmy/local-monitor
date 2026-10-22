import Foundation
import CoreFoundation
import Darwin

// Value-only calculations are kept separate from the native reads for deterministic tests.
struct CPUTicks: Equatable {
    let user: UInt32
    let system: UInt32
    let idle: UInt32
    let nice: UInt32

    func utilization(since previous: CPUTicks?) -> Double? {
        guard let previous,
              user >= previous.user, system >= previous.system,
              idle >= previous.idle, nice >= previous.nice else { return nil }
        let busy = UInt64(user - previous.user) + UInt64(system - previous.system) + UInt64(nice - previous.nice)
        let total = busy + UInt64(idle - previous.idle)
        guard total > 0 else { return nil }
        return Double(busy) / Double(total) * 100
    }
}

struct InterfaceCounters: Equatable {
    let index: UInt32
    let received: UInt64
    let sent: UInt64
}

struct NetworkBaseline {
    let uptime: Double
    let interfaces: [InterfaceCounters]
}

enum SystemMetrics {
    static func memory(totalBytes: UInt64, pageSize: UInt64, internalPages: UInt64, purgeablePages: UInt64, wiredPages: UInt64, compressorPages: UInt64, swapUsedBytes: UInt64?, pressure: MemoryPressure) -> MemoryStats {
        let appPages = internalPages > purgeablePages ? internalPages - purgeablePages : 0
        let usedPages = saturatingAdd(saturatingAdd(appPages, wiredPages), compressorPages)
        let used = min(totalBytes, saturatingMultiply(usedPages, pageSize))
        return MemoryStats(totalBytes: totalBytes, usedBytes: used, availableBytes: totalBytes - used, compressedBytes: min(totalBytes, saturatingMultiply(compressorPages, pageSize)), swapUsedBytes: swapUsedBytes, pressure: pressure)
    }

    static func network(interfaces: [InterfaceCounters], uptime: Double, previous: NetworkBaseline?) -> NetworkStats {
        // The native reader already deduplicates indices. Keep the calculation safe for fixtures too.
        let unique = Dictionary(interfaces.map { ($0.index, $0) }, uniquingKeysWith: { first, _ in first })
        let received = unique.values.reduce(UInt64(0)) { saturatingAdd($0, $1.received) }
        let sent = unique.values.reduce(UInt64(0)) { saturatingAdd($0, $1.sent) }
        var download: Double?
        var upload: Double?
        var interval: Double?
        if let previous, uptime.isFinite, previous.uptime.isFinite, uptime > previous.uptime {
            let old = Dictionary(previous.interfaces.map { ($0.index, $0) }, uniquingKeysWith: { first, _ in first })
            // Interface changes establish a fresh baseline rather than spiking the total rate.
            if !unique.isEmpty, Set(unique.keys) == Set(old.keys) {
                var receivedDelta: UInt64 = 0
                var sentDelta: UInt64 = 0
                var valid = true
                for (index, current) in unique {
                    guard let before = old[index], current.received >= before.received, current.sent >= before.sent else {
                        valid = false
                        break
                    }
                    receivedDelta = saturatingAdd(receivedDelta, current.received - before.received)
                    sentDelta = saturatingAdd(sentDelta, current.sent - before.sent)
                }
                if valid {
                    let elapsed = uptime - previous.uptime
                    download = Double(receivedDelta) / elapsed
                    upload = Double(sentDelta) / elapsed
                    interval = elapsed
                }
            }
        }
        return NetworkStats(receivedBytes: received, sentBytes: sent, downloadBytesPerSecond: download, uploadBytesPerSecond: upload, intervalSeconds: interval)
    }

    static func pressure(raw: Int32?) -> MemoryPressure {
        switch raw {
        case 1: return .normal
        case 2: return .warning
        case 4: return .critical
        default: return .unknown
        }
    }

    static func gpuUtilization(statistics: [String: Any]) -> Double? {
        // Only known percentage-valued keys. Never infer a percent from clocks, cycles or busy time.
        for key in ["Device Utilization %", "GPU Activity(%)"] {
            guard let number = statistics[key] as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID() else { continue }
            let value = number.doubleValue
            if value.isFinite, (0...100).contains(value) { return value }
        }
        return nil
    }

    static func isEligibleInterface(name: String, flags: UInt32, family: UInt8) -> Bool {
        // enN is macOS's physical Ethernet/Wi-Fi naming. Do not sum VPN/bridge/AWDL
        // overlays on top of their underlying enN traffic. No addresses are inspected.
        let suffix = name.dropFirst(2)
        return family == UInt8(AF_LINK) && flags & UInt32(IFF_UP) != 0 && flags & UInt32(IFF_LOOPBACK) == 0
            && name.hasPrefix("en") && !suffix.isEmpty && suffix.allSatisfy { $0.isASCII && $0.isNumber }
    }

    static func saturatingAdd(_ a: UInt64, _ b: UInt64) -> UInt64 {
        let result = a.addingReportingOverflow(b)
        return result.overflow ? UInt64.max : result.partialValue
    }

    static func saturatingMultiply(_ a: UInt64, _ b: UInt64) -> UInt64 {
        let result = a.multipliedReportingOverflow(by: b)
        return result.overflow ? UInt64.max : result.partialValue
    }
}
