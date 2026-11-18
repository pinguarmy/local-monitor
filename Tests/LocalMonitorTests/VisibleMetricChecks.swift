import Foundation
import SystemCore
import DeviceCore

// Visible-metric rule checks: nil metrics produce no rows, no placeholders and no unreadable
// explanations. Called by PresentationRunner, which owns the assertion count; no @main here.

/// True when the text contains CJK ideographs.
func containsCJK(_ text: String) -> Bool {
    text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) || (0x3000...0x303F).contains($0.value) }
}

/// System rows, device rows and the placeholder scan, in both languages.
@MainActor
func runVisibleMetricChecks(_ check: (Bool, String) -> Void) {
    L10n.language = .simplifiedChinese
    for invalid in [Double.nan, Double.infinity, -Double.infinity, -1, Double.greatestFiniteMagnitude] {
        check(VisibleMetrics.uptimeLabel(invalid) == nil, "invalid uptime omitted without integer-conversion trap")
    }
    check(VisibleMetrics.uptimeLabel(0) == "0 分", "zh zero uptime is valid")
    check(VisibleMetrics.uptimeLabel(90061.9) == "1 天 1 小时", "zh fractional uptime truncates safely")
    check(VisibleMetrics.uptimeLabel(3900) == "1 小时 5 分", "zh hours and minutes uptime")
    L10n.language = .english
    check(VisibleMetrics.uptimeLabel(0) == "0 min", "en zero uptime is valid")
    check(VisibleMetrics.uptimeLabel(90061.9) == "1 d 1 h", "en fractional uptime truncates safely")
    check(VisibleMetrics.uptimeLabel(3900) == "1 h 5 min", "en hours and minutes uptime")

    for language in AppLanguage.allCases {
        L10n.language = language
        let tag = language.rawValue

        // CPU: on the first frame usage is nil and its row is absent; load lists only sampled windows.
        let firstFrameCPU = CPUStats(logicalCoreCount: 8, physicalCoreCount: 4, usagePercent: nil,
                                     loadAverage1: 1.5, loadAverage5: nil, loadAverage15: 0.8)
        let firstCPURows = VisibleMetrics.cpuRows(firstFrameCPU)
        check(!firstCPURows.contains { $0.title == L10n.cpuUsage }, "cpu first frame omits usage row (\(tag))")
        check(VisibleMetrics.cpuGauge(firstFrameCPU) == nil, "cpu gauge absent without usage (\(tag))")
        check(firstCPURows.contains { $0.title == L10n.cpuCores && $0.value == L10n.coreCounts(logical: 8, physical: 4) },
              "cpu cores row always present (\(tag))")
        check(firstCPURows.contains { $0.title == L10n.cpuLoad && $0.value.contains("1.50") && $0.value.contains("0.80") && !$0.value.contains("—") },
              "cpu load row keeps only sampled entries (\(tag))")
        let sampledCPU = CPUStats(logicalCoreCount: 8, physicalCoreCount: nil, usagePercent: 42.5,
                                  loadAverage1: nil, loadAverage5: nil, loadAverage15: nil)
        let sampledCPURows = VisibleMetrics.cpuRows(sampledCPU)
        check(sampledCPURows.first == MetricItem(title: L10n.cpuUsage, value: "42.5%"), "cpu usage is the first row once sampled (\(tag))")
        check(VisibleMetrics.cpuGauge(sampledCPU)?.fraction == 0.425, "cpu gauge follows usage (\(tag))")
        check(!sampledCPURows.contains { $0.title == L10n.cpuLoad }, "cpu load row hidden when nothing sampled (\(tag))")
        check(VisibleMetrics.cpuRows(nil).isEmpty, "cpu group hidden when nil (\(tag))")

        // GPU: without utilization only the model remains; nothing read hides the group.
        let gpuNoUtil = VisibleMetrics.gpuRows(GPUStats(name: "Apple M4", utilizationPercent: nil))
        check(gpuNoUtil == [MetricItem(title: L10n.gpuModel, value: "Apple M4")], "gpu without utilization keeps only the name (\(tag))")
        check(VisibleMetrics.gpuRows(GPUStats(name: "Apple M4", utilizationPercent: 33)).count == 2,
              "gpu utilization row appears when sampled (\(tag))")
        check(VisibleMetrics.gpuRows(GPUStats(name: nil, utilizationPercent: nil)).isEmpty, "gpu group hidden when nothing read (\(tag))")
        check(VisibleMetrics.gpuRows(nil).isEmpty, "gpu nil hidden (\(tag))")

        // Memory: swap hidden when nil, pressure hidden when unknown and toned otherwise.
        let gib: UInt64 = 1024 * 1024 * 1024
        let memoryNoSwap = MemoryStats(totalBytes: 16 * gib, usedBytes: 8 * gib, availableBytes: 8 * gib,
                                       compressedBytes: gib, swapUsedBytes: nil, pressure: .unknown)
        let memoryNoSwapRows = VisibleMetrics.memoryRows(memoryNoSwap)
        check(!memoryNoSwapRows.contains { $0.title == L10n.swap }, "swap row hidden when nil (\(tag))")
        check(!memoryNoSwapRows.contains { $0.title == L10n.memoryPressure }, "unknown pressure hidden (\(tag))")
        check(memoryNoSwapRows.first?.title == L10n.usedOfTotal, "memory used/total first (\(tag))")
        check(VisibleMetrics.memoryGauge(memoryNoSwap)?.fraction == 0.5, "memory gauge ratio (\(tag))")
        let memorySwap = MemoryStats(totalBytes: 16 * gib, usedBytes: 8 * gib, availableBytes: 8 * gib,
                                     compressedBytes: gib, swapUsedBytes: 512 * 1024 * 1024, pressure: .warning)
        let memorySwapRows = VisibleMetrics.memoryRows(memorySwap)
        check(memorySwapRows.contains { $0.title == L10n.swap }, "swap row appears when sampled (\(tag))")
        check(memorySwapRows.contains { $0.title == L10n.memoryPressure && $0.value == L10n.memoryPressureLevel(.warning) && $0.tone == .warning },
              "memory pressure row toned (\(tag))")
        check(VisibleMetrics.memoryRows(nil).isEmpty && VisibleMetrics.memoryGauge(nil) == nil, "memory nil hidden (\(tag))")

        // Disk: Used / Total with a gauge, plus Available. Used saturates at zero.
        let disk = DiskStats(totalBytes: 1000 * gib, freeBytes: 300 * gib, availableBytes: 250 * gib)
        let diskRows = VisibleMetrics.diskRows(disk)
        check(diskRows.count == 2, "disk shows used/total and available (\(tag))")
        check(diskRows.first?.title == L10n.usedOfTotal, "disk used/total first (\(tag))")
        check(diskRows.first?.value == L10n.pair(MonitorFormat.bytes(750 * gib), MonitorFormat.bytes(1000 * gib)),
              "disk used = total - available (\(tag))")
        check(diskRows.last == MetricItem(title: L10n.available, value: MonitorFormat.bytes(250 * gib)), "disk available row (\(tag))")
        check(VisibleMetrics.diskGauge(disk)?.fraction == 0.75, "disk gauge ratio (\(tag))")
        let oddDisk = DiskStats(totalBytes: 10, freeBytes: 20, availableBytes: 20)
        check(VisibleMetrics.diskUsedBytes(oddDisk) == 0, "disk used saturates (\(tag))")
        check(VisibleMetrics.diskGauge(oddDisk)?.fraction == 0, "disk gauge with saturated usage (\(tag))")
        check(VisibleMetrics.diskGauge(DiskStats(totalBytes: 0, freeBytes: 0, availableBytes: 0)) == nil, "no disk gauge for zero capacity (\(tag))")
        check(VisibleMetrics.diskRows(nil).isEmpty && VisibleMetrics.diskGauge(nil) == nil, "disk nil hidden (\(tag))")

        // Network: rates hidden until two samples exist; totals always shown.
        let netFirst = NetworkStats(receivedBytes: 100, sentBytes: 50,
                                    downloadBytesPerSecond: nil, uploadBytesPerSecond: nil, intervalSeconds: nil)
        let netFirstRows = VisibleMetrics.networkRows(netFirst)
        check(netFirstRows.count == 1 && netFirstRows[0].title == L10n.receivedSent, "network rates hidden until sampled (\(tag))")
        let netLater = NetworkStats(receivedBytes: 100, sentBytes: 50,
                                    downloadBytesPerSecond: 1024, uploadBytesPerSecond: 512, intervalSeconds: 2)
        let netLaterRows = VisibleMetrics.networkRows(netLater)
        check(netLaterRows.contains { $0.title == L10n.download && $0.value.hasSuffix("/s") }
                && netLaterRows.contains { $0.title == L10n.upload },
              "network rates appear once sampled (\(tag))")
        check(VisibleMetrics.networkRows(nil).isEmpty, "network nil hidden (\(tag))")

        // Machine rows: thermal hidden when unknown, toned when elevated; Low Power Mode always present.
        let calm = SystemSnapshot(timestamp: Date(), cpu: nil, gpu: nil, memory: nil, disk: nil, network: nil,
                                  thermalState: .unknown, isLowPowerModeEnabled: false, uptimeSeconds: 60, limitations: [])
        let calmRows = VisibleMetrics.machineRows(calm)
        check(!calmRows.contains { $0.title == L10n.thermalState }, "unknown thermal state hidden (\(tag))")
        check(calmRows.contains { $0.title == L10n.lowPowerMode && $0.value == L10n.onOff(false) }, "low power row (\(tag))")
        let hot = SystemSnapshot(timestamp: Date(), cpu: nil, gpu: nil, memory: nil, disk: nil, network: nil,
                                 thermalState: .serious, isLowPowerModeEnabled: true, uptimeSeconds: .nan, limitations: [])
        let hotRows = VisibleMetrics.machineRows(hot)
        check(hotRows.contains { $0.title == L10n.thermalState && $0.tone == .critical }, "serious thermal state is critical tone (\(tag))")
        check(!hotRows.contains { $0.title == L10n.uptime }, "invalid uptime row hidden (\(tag))")

        // Devices with values: every field becomes a row.
        let fullDevice = ConnectedDeviceSnapshot(
            id: "0", productType: "iPhone16,2", productVersion: "18.1", kind: .iPhone,
            batteryPercentage: 80, chargingState: .charging, externalPowerConnected: true,
            temperatureCelsius: 30.5, cycleCount: 120, designCapacityMAh: 4000, fullChargeCapacityMAh: 3600,
            batteryDetailsStatus: "available", batteryDetailsSource: "diagnostics_relay IORegistry AppleSmartBattery",
            message: nil
        )
        let fullRows = VisibleMetrics.deviceRows(fullDevice)
        check(fullRows.contains { $0.title == L10n.osVersion && $0.value == "iOS 18.1" }, "device version row (\(tag))")
        check(fullRows.contains { $0.title == L10n.chargingStatus && $0.value == L10n.chargingState(.charging) }, "device charging row (\(tag))")
        check(fullRows.contains { $0.title == L10n.externalPower && $0.value == L10n.connected(true) }, "device external power row (\(tag))")
        check(fullRows.contains { $0.title == L10n.batteryTemperature && $0.value == "30.5 °C" }, "device temperature row (\(tag))")
        check(fullRows.contains { $0.title == L10n.cycleCount && $0.value == "120" }, "device cycle row (\(tag))")
        check(fullRows.contains { $0.title == L10n.deviceFullChargeCapacity && $0.value == "3600 mAh" }, "device full charge row (\(tag))")
        check(fullRows.contains { $0.title == L10n.designCapacity && $0.value == "4000 mAh" }, "device design row (\(tag))")
        check(fullRows.contains { $0.title == L10n.deviceCapacityRatio && $0.value == "90.0%" }, "device capacity ratio row (\(tag))")
        check(VisibleMetrics.deviceRows(ConnectedDeviceSnapshot(id: "0", productVersion: "18.1", kind: .iPad))
                .contains { $0.title == L10n.osVersion && $0.value == "iPadOS 18.1" }, "ipad version label (\(tag))")

        // Devices without values: a device with only kind and charge produces no rows.
        check(VisibleMetrics.deviceRows(ConnectedDeviceSnapshot(id: "0", kind: .iPad, batteryPercentage: 55)).isEmpty,
              "device without values renders no rows (\(tag))")

        // Partial diagnostics: source/debug paths and the message never become rows.
        let partialDevice = ConnectedDeviceSnapshot(
            id: "1", kind: .iPhone, batteryPercentage: 66, chargingState: .notCharging,
            batteryDetailsStatus: "partial", batteryDetailsSource: "/very/long/debug/path AppleSmartBattery",
            message: "Some detailed fields failed"
        )
        let partialRows = VisibleMetrics.deviceRows(partialDevice)
        check(partialRows.count == 1 && partialRows[0].title == L10n.chargingStatus,
              "partial diagnostics failure keeps only real values (\(tag))")
        check(!partialRows.contains { $0.value.contains("debug") || $0.value.contains("AppleSmartBattery") || $0.value.contains("failed") },
              "no source path or failure explanation in rows (\(tag))")

        // Placeholder scan over every row set, in this language.
        let bannedZh = ["未采到", "未取得", "接口不提供", "等待", "不支持", "开发者模式", "未知"]
        let bannedEn = ["not sampled", "unavailable", "n/a", "waiting", "not supported", "developer mode", "unknown", "—"]
        let allRows = [firstCPURows, sampledCPURows, gpuNoUtil, memorySwapRows, memoryNoSwapRows, diskRows,
                       netFirstRows, netLaterRows, calmRows, hotRows, fullRows, partialRows].flatMap { $0 }
        check(!allRows.isEmpty, "row set non-empty for placeholder scan (\(tag))")
        for row in allRows {
            let value = row.value.lowercased()
            check(!bannedZh.contains { value.contains($0) } && !bannedEn.contains { value.contains($0) },
                  "row '\(row.title)' has no placeholder text (\(tag))")
            check(!row.title.isEmpty && !row.value.isEmpty, "row '\(row.title)' is not empty (\(tag))")
            if language == .english {
                check(!containsCJK(row.title), "row title '\(row.title)' has no Chinese in English (\(tag))")
            }
        }
        if language == .english {
            // Byte counts are formatted by Foundation in the system locale, so only non-byte values are scanned.
            for row in [firstCPURows, sampledCPURows, calmRows, hotRows, fullRows, partialRows].flatMap({ $0 }) {
                check(!containsCJK(row.value), "row value '\(row.value)' has no Chinese in English (\(tag))")
            }
        }

        // Devices note: no explanation of unsupported metrics.
        check(!VisibleMetrics.deviceNote.isEmpty, "device note present (\(tag))")
        check(!VisibleMetrics.deviceNote.contains("开发者模式") && !VisibleMetrics.deviceNote.lowercased().contains("developer mode"),
              "device note drops developer-mode explanation (\(tag))")
        check(!VisibleMetrics.deviceNote.contains("CPU") && !VisibleMetrics.deviceNote.contains("内存")
                && !VisibleMetrics.deviceNote.lowercased().contains("memory"),
              "device note drops unsupported-metrics explanation (\(tag))")
    }

    // Spot-check natural formatting in each language.
    L10n.language = .english
    check(L10n.coreCounts(logical: 8, physical: 4) == "8 logical · 4 physical", "en core counts")
    check(VisibleMetrics.cpuRows(CPUStats(logicalCoreCount: 8, physicalCoreCount: 4, usagePercent: nil,
                                          loadAverage1: 1.5, loadAverage5: nil, loadAverage15: 0.8))
            .contains { $0.title == "Load" && $0.value == "1m 1.50 · 15m 0.80" }, "en load averages")
    check(VisibleMetrics.diskRows(DiskStats(totalBytes: 1, freeBytes: 1, availableBytes: 1)).map { $0.title } == ["Used / Total", "Available"],
          "en disk titles")
    L10n.language = .simplifiedChinese
    check(L10n.coreCounts(logical: 8, physical: 4) == "8 逻辑核 · 4 物理核", "zh core counts")
    check(VisibleMetrics.cpuRows(CPUStats(logicalCoreCount: 8, physicalCoreCount: 4, usagePercent: nil,
                                          loadAverage1: 1.5, loadAverage5: nil, loadAverage15: 0.8))
            .contains { $0.title == "负载" && $0.value == "1分 1.50 · 15分 0.80" }, "zh load averages")
    check(VisibleMetrics.diskRows(DiskStats(totalBytes: 1, freeBytes: 1, availableBytes: 1)).map { $0.title } == ["已用 / 总量", "可用"],
          "zh disk titles")
    check(VisibleMetrics.chargingLabel(.full) == "已充满" && VisibleMetrics.chargingLabel(.notCharging) == "未在充电", "zh charging labels")
}
