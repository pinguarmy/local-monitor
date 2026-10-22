import Foundation
import SystemCore
import DeviceCore

// 可见指标纯规则检查：nil 指标不渲染、不放占位与不可读解释文案。
// 由 PresentationRunner 调用并汇入其断言计数，本文件不含 @main。

/// 覆盖：系统页各组 nil 过滤、设备有值全出/缺值整行省略、
/// 行值不含 source/debug 路径与“未采到/未取得/接口不提供/不支持”等占位。
func runVisibleMetricChecks(_ check: (Bool, String) -> Void) {
    for invalid in [Double.nan, Double.infinity, -Double.infinity, -1, Double.greatestFiniteMagnitude] {
        check(VisibleMetrics.uptimeLabel(invalid) == nil, "invalid uptime omitted without integer-conversion trap")
    }
    check(VisibleMetrics.uptimeLabel(0) == "0 分", "zero uptime is valid")
    check(VisibleMetrics.uptimeLabel(90061.9) == "1 天 1 小时", "fractional uptime truncates safely")
    // 系统页 · CPU：首帧 usage 为 nil 时该行不出现，负载只列已采到的项。
    let firstFrameCPU = CPUStats(logicalCoreCount: 8, physicalCoreCount: 4, usagePercent: nil,
                                 loadAverage1: 1.5, loadAverage5: nil, loadAverage15: 0.8)
    let firstCPURows = VisibleMetrics.cpuRows(firstFrameCPU)
    check(!firstCPURows.contains { $0.title == "使用率" }, "cpu first frame omits usage row")
    check(firstCPURows.contains { $0.title == "核心" && $0.value.contains("8 逻辑核") && $0.value.contains("4 物理核") },
          "cpu cores row always present")
    check(firstCPURows.contains { $0.title == "负载" && $0.value.contains("1.50") && $0.value.contains("0.80") && !$0.value.contains("—") },
          "cpu load row keeps only sampled entries")
    let sampledCPU = CPUStats(logicalCoreCount: 8, physicalCoreCount: nil, usagePercent: 42.5,
                              loadAverage1: nil, loadAverage5: nil, loadAverage15: nil)
    check(VisibleMetrics.cpuRows(sampledCPU).contains { $0.title == "使用率" && $0.value == "42.5%" },
          "cpu usage row appears once sampled")
    check(VisibleMetrics.cpuRows(nil).isEmpty, "cpu group hidden when nil")

    // 系统页 · GPU：利用率为 nil 时只留有值的型号；全空则整组隐藏。
    let gpuNoUtil = VisibleMetrics.gpuRows(GPUStats(name: "Apple M4", utilizationPercent: nil))
    check(gpuNoUtil.count == 1 && gpuNoUtil[0].title == "型号" && gpuNoUtil[0].value == "Apple M4",
          "gpu without utilization keeps only the name")
    check(VisibleMetrics.gpuRows(GPUStats(name: "Apple M4", utilizationPercent: 33)).count == 2,
          "gpu utilization row appears when sampled")
    check(VisibleMetrics.gpuRows(GPUStats(name: nil, utilizationPercent: nil)).isEmpty,
          "gpu group hidden when nothing read")
    check(VisibleMetrics.gpuRows(nil).isEmpty, "gpu nil hidden")

    // 系统页 · 内存：swap 为 nil 时该行隐藏；nil 快照整组隐藏。
    let memoryNoSwap = MemoryStats(totalBytes: 16 * 1024 * 1024 * 1024, usedBytes: 8 * 1024 * 1024 * 1024,
                                   availableBytes: 8 * 1024 * 1024 * 1024, compressedBytes: 1024 * 1024 * 1024,
                                   swapUsedBytes: nil, pressure: .normal)
    check(!VisibleMetrics.memoryRows(memoryNoSwap).contains { $0.title == "交换" }, "swap row hidden when nil")
    let memorySwap = MemoryStats(totalBytes: 16 * 1024 * 1024 * 1024, usedBytes: 8 * 1024 * 1024 * 1024,
                                 availableBytes: 8 * 1024 * 1024 * 1024, compressedBytes: 1024 * 1024 * 1024,
                                 swapUsedBytes: 512 * 1024 * 1024, pressure: .warning)
    check(VisibleMetrics.memoryRows(memorySwap).contains { $0.title == "交换" }, "swap row appears when sampled")
    check(VisibleMetrics.memoryRows(nil).isEmpty, "memory nil hidden")

    // 系统页 · 磁盘：nil 整组隐藏，有值三行。
    check(VisibleMetrics.diskRows(nil).isEmpty, "disk nil hidden")
    check(VisibleMetrics.diskRows(DiskStats(totalBytes: 1, freeBytes: 1, availableBytes: 1)).count == 3,
          "disk rows when sampled")

    // 系统页 · 网络：速率为 nil 时隐藏直到有值，累计行保留。
    let netFirst = NetworkStats(receivedBytes: 100, sentBytes: 50,
                                downloadBytesPerSecond: nil, uploadBytesPerSecond: nil, intervalSeconds: nil)
    let netFirstRows = VisibleMetrics.networkRows(netFirst)
    check(netFirstRows.count == 1 && netFirstRows[0].title == "累计收 / 发",
          "network rates hidden until sampled")
    let netLater = NetworkStats(receivedBytes: 100, sentBytes: 50,
                                downloadBytesPerSecond: 1024, uploadBytesPerSecond: 512, intervalSeconds: 2)
    let netLaterRows = VisibleMetrics.networkRows(netLater)
    check(netLaterRows.contains { $0.title == "下载" } && netLaterRows.contains { $0.title == "上传" },
          "network rates appear once sampled")
    check(VisibleMetrics.networkRows(nil).isEmpty, "network nil hidden")

    // 设备页 · 有值：所有字段成行，数值格式正确。
    let fullDevice = ConnectedDeviceSnapshot(
        id: "0", productType: "iPhone16,2", productVersion: "18.1", kind: .iPhone,
        batteryPercentage: 80, chargingState: .charging, externalPowerConnected: true,
        temperatureCelsius: 30.5, cycleCount: 120, designCapacityMAh: 4000, fullChargeCapacityMAh: 3600,
        batteryDetailsStatus: "available", batteryDetailsSource: "diagnostics_relay IORegistry AppleSmartBattery",
        message: nil
    )
    let fullRows = VisibleMetrics.deviceRows(fullDevice)
    check(fullRows.contains { $0.title == "系统版本" && $0.value == "iOS 18.1" }, "device version row")
    check(fullRows.contains { $0.title == "充电状态" && $0.value == "充电中" }, "device charging row")
    check(fullRows.contains { $0.title == "外接电源" && $0.value == "已连接" }, "device external power row")
    check(fullRows.contains { $0.title == "电池温度" && $0.value == "30.5 °C" }, "device temperature row")
    check(fullRows.contains { $0.title == "循环次数" && $0.value == "120" }, "device cycle row")
    check(fullRows.contains { $0.title == "实际满充容量" && $0.value == "3600 mAh" }, "device full charge row")
    check(fullRows.contains { $0.title == "设计容量" && $0.value == "4000 mAh" }, "device design row")
    check(fullRows.contains { $0.title == "容量比 · 估算" && $0.value == "90.0%" }, "device capacity ratio row")
    check(VisibleMetrics.deviceRows(ConnectedDeviceSnapshot(id: "0", productVersion: "18.1", kind: .iPad))
            .contains { $0.title == "系统版本" && $0.value == "iPadOS 18.1" }, "ipad version label")

    // 设备页 · 缺值：整行省略，只有 kind/电量的设备不产生任何行。
    let sparseRows = VisibleMetrics.deviceRows(ConnectedDeviceSnapshot(id: "0", kind: .iPad, batteryPercentage: 55))
    check(sparseRows.isEmpty, "device without values renders no rows")

    // 设备页 · partial 诊断：source/debug 路径与 message 缺失解释不进入任何行。
    let partialDevice = ConnectedDeviceSnapshot(
        id: "1", kind: .iPhone, batteryPercentage: 66, chargingState: .notCharging,
        batteryDetailsStatus: "partial", batteryDetailsSource: "/very/long/debug/path AppleSmartBattery",
        message: "部分字段详细读取失败"
    )
    let partialRows = VisibleMetrics.deviceRows(partialDevice)
    check(partialRows.count == 1 && partialRows[0].title == "充电状态",
          "partial diagnostics failure keeps only real values")
    check(!partialRows.contains { $0.value.contains("debug") || $0.value.contains("AppleSmartBattery") || $0.value.contains("失败") },
          "no source path or failure explanation in rows")

    // 全量扫描：任何行值都不含占位或不可读解释文案。
    let banned = ["未采到", "未取得", "接口不提供", "等待", "不支持", "开发者模式"]
    let allRows = [firstCPURows, gpuNoUtil, netFirstRows, fullRows, partialRows].flatMap { $0 }
    check(!allRows.isEmpty, "row set non-empty for placeholder scan")
    for row in allRows {
        check(!banned.contains { row.value.contains($0) }, "row '\(row.title)' has no placeholder text")
    }

    // 设备页底部说明：不解释未支持的指标。
    check(!VisibleMetrics.deviceNote.contains("开发者模式"), "device note drops developer-mode explanation")
    check(!VisibleMetrics.deviceNote.contains("CPU") && !VisibleMetrics.deviceNote.contains("内存"),
          "device note drops unsupported-metrics explanation")
}
