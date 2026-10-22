import SwiftUI
import SystemCore
import DeviceCore

// 本文件只包含“系统”和“设备”两个页签的 SwiftUI 视图与可见指标纯规则。
// 数据模型（SystemSnapshot / DeviceSnapshot 等）由 SystemCore、DeviceCore 提供，
// 调度、采样生命周期和面板组装由外层负责，这里不做任何采集。
// 可见性原则：任何 nil 指标直接省略，不放“未采到 / 未取得 / 接口不提供”等占位文案。

// MARK: - 共享行样式与格式化（仅本文件使用）

/// 与电池页一致的两列指标行：左标题右数值，等宽数字。
private struct MonitorMetricRow: View {
    let title: String
    let value: String
    var valueColor: Color? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .foregroundStyle(valueColor ?? Color.primary)
        }
        .font(.system(size: 12))
    }
}

/// 小节标题。
private struct MonitorGroupHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}

private enum MonitorFormat {
    static func bytes(_ value: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: Int64(clamping: value))
    }

    static func bytesPerSecond(_ value: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        formatter.allowsNonnumericFormatting = false
        let safe = value.isFinite ? min(Double(Int64.max / 2), max(0, value)) : 0
        return formatter.string(fromByteCount: Int64(safe)) + "/s"
    }

    static func percent(_ value: Double) -> String {
        String(format: "%.1f%%", value)
    }

    static func uptime(_ seconds: Double) -> String? {
        guard seconds.isFinite, seconds >= 0, let total = Int(exactly: seconds.rounded(.towardZero)) else { return nil }
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        if days > 0 { return "\(days) 天 \(hours) 小时" }
        if hours > 0 { return "\(hours) 小时 \(minutes) 分" }
        return "\(minutes) 分"
    }
}

// MARK: - 可见指标纯规则（视图与 VisibleMetricChecks 测试共用）

/// 只列出实际读到的行；缺失的指标不出现在列表里，界面自然不渲染，
/// 也不放任何“未采到 / 未取得 / 接口不提供 / 等待采样”的占位。
enum VisibleMetrics {
    /// 设备页底部固定说明：只读与编号用途。不解释取不到的指标。
    static let deviceNote = "本页只读设备信息，不自动配对或读取个人内容。设备编号仅用于当前列表。"

    static func uptimeLabel(_ seconds: Double) -> String? { MonitorFormat.uptime(seconds) }

    static func chargingLabel(_ state: DeviceChargingState) -> String {
        switch state.rawValue {
        case "charging": return "充电中"
        case "full": return "已充满"
        case "notCharging": return "未在充电"
        default: return "未知"
        }
    }

    /// CPU 行：首个样本没有差分基准，usagePercent 为 nil 时该行暂不出现；
    /// 负载只列已采到的项，全缺则整行省略。
    static func cpuRows(_ cpu: CPUStats?) -> [(title: String, value: String)] {
        guard let cpu else { return [] }
        var rows: [(title: String, value: String)] = []
        if let usage = cpu.usagePercent {
            rows.append(("使用率", MonitorFormat.percent(usage)))
        }
        rows.append(("核心", "\(cpu.logicalCoreCount) 逻辑核"
            + (cpu.physicalCoreCount.map { " · \($0) 物理核" } ?? "")))
        let loads = [("1分", cpu.loadAverage1), ("5分", cpu.loadAverage5), ("15分", cpu.loadAverage15)]
            .compactMap { label, value in value.map { "\(label) \(String(format: "%.2f", $0))" } }
        if !loads.isEmpty {
            rows.append(("负载", loads.joined(separator: " · ")))
        }
        return rows
    }

    /// GPU 行：利用率常因接口限制取不到，nil 时只保留有值的行（如型号）。
    static func gpuRows(_ gpu: GPUStats?) -> [(title: String, value: String)] {
        guard let gpu else { return [] }
        var rows: [(title: String, value: String)] = []
        if let name = gpu.name, !name.isEmpty {
            rows.append(("型号", name))
        }
        if let utilization = gpu.utilizationPercent {
            rows.append(("利用率", MonitorFormat.percent(utilization)))
        }
        return rows
    }

    /// 内存行：swap 取不到时整行隐藏。内存压力带颜色，由视图单独渲染。
    static func memoryRows(_ memory: MemoryStats?) -> [(title: String, value: String)] {
        guard let memory else { return [] }
        var rows: [(title: String, value: String)] = [
            ("已用 / 总量", "\(MonitorFormat.bytes(memory.usedBytes)) / \(MonitorFormat.bytes(memory.totalBytes))"),
            ("可用", MonitorFormat.bytes(memory.availableBytes)),
            ("已压缩", MonitorFormat.bytes(memory.compressedBytes)),
        ]
        if let swap = memory.swapUsedBytes {
            rows.append(("交换", MonitorFormat.bytes(swap)))
        }
        return rows
    }

    static func diskRows(_ disk: DiskStats?) -> [(title: String, value: String)] {
        guard let disk else { return [] }
        return [
            ("总容量", MonitorFormat.bytes(disk.totalBytes)),
            ("可用", MonitorFormat.bytes(disk.availableBytes)),
            ("剩余", MonitorFormat.bytes(disk.freeBytes)),
        ]
    }

    /// 网络行：速率依赖两次采样的差分，nil 时隐藏直到有值。
    static func networkRows(_ network: NetworkStats?) -> [(title: String, value: String)] {
        guard let network else { return [] }
        var rows: [(title: String, value: String)] = []
        if let download = network.downloadBytesPerSecond {
            rows.append(("下载", MonitorFormat.bytesPerSecond(download)))
        }
        if let upload = network.uploadBytesPerSecond {
            rows.append(("上传", MonitorFormat.bytesPerSecond(upload)))
        }
        rows.append(("累计收 / 发", "\(MonitorFormat.bytes(network.receivedBytes)) / \(MonitorFormat.bytes(network.sentBytes))"))
        return rows
    }

    /// 设备卡片行：只含实际读到的值。详细来源路径、batteryDetailsStatus 解释
    /// 与 message 缺失字段说明一律不进入列表；诊断部分失败不当作整卡失败。
    static func deviceRows(_ device: ConnectedDeviceSnapshot) -> [(title: String, value: String)] {
        var rows: [(title: String, value: String)] = []
        if let version = device.productVersion, !version.isEmpty {
            rows.append(("系统版本", "\(device.kind == .iPad ? "iPadOS" : "iOS") \(version)"))
        }
        if let state = device.chargingState {
            rows.append(("充电状态", chargingLabel(state)))
        }
        if let external = device.externalPowerConnected {
            rows.append(("外接电源", external ? "已连接" : "未连接"))
        }
        if let temperature = device.temperatureCelsius {
            rows.append(("电池温度", String(format: "%.1f °C", temperature)))
        }
        if let cycles = device.cycleCount {
            rows.append(("循环次数", String(cycles)))
        }
        if let full = device.fullChargeCapacityMAh {
            rows.append(("实际满充容量", "\(full) mAh"))
        }
        if let design = device.designCapacityMAh {
            rows.append(("设计容量", "\(design) mAh"))
        }
        if let full = device.fullChargeCapacityMAh, let design = device.designCapacityMAh, design > 0 {
            rows.append(("容量比 · 估算", String(format: "%.1f%%", Double(full) / Double(design) * 100)))
        }
        return rows
    }
}

// MARK: - 系统页

@MainActor
struct SystemSection: View {
    let snapshot: SystemSnapshot?
    let isSampling: Bool

    // ThermalState / MemoryPressure 是 String 原始值枚举，
    // 按 rawValue 映射并保留 default 分支，未来新增 case 时显示“未知”而不是编译失败。

    private func thermalLabel(_ state: ThermalState) -> String {
        switch state.rawValue {
        case "nominal": return "正常"
        case "fair": return "偏高"
        case "serious": return "严重"
        case "critical": return "危急"
        default: return "未知"
        }
    }

    private func thermalColor(_ state: ThermalState) -> Color? {
        switch state.rawValue {
        case "fair": return .orange
        case "serious", "critical": return .red
        default: return nil
        }
    }

    private func pressureLabel(_ pressure: MemoryPressure) -> String {
        switch pressure.rawValue {
        case "normal": return "正常"
        case "warning": return "紧张"
        case "critical": return "危急"
        default: return "未知"
        }
    }

    private func pressureColor(_ pressure: MemoryPressure) -> Color? {
        switch pressure.rawValue {
        case "warning": return .orange
        case "critical": return .red
        default: return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 头部：标题 + 采样状态 / 上次采样时间
            HStack(alignment: .firstTextBaseline) {
                Text("系统").font(.headline)
                Spacer()
                if isSampling {
                    Text("采样中…").font(.system(size: 10)).foregroundStyle(.secondary)
                } else if let snapshot {
                    HStack(spacing: 4) {
                        Text("更新于")
                        Text(snapshot.timestamp, style: .time).monospacedDigit()
                    }
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }

            if let snapshot {
                systemGroups(snapshot)
            } else {
                Text("尚未采样。打开面板后开始采集。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 各组只在自己的行非空时出现；分隔线只插在两个可见组之间。
    @ViewBuilder
    private func systemGroups(_ snapshot: SystemSnapshot) -> some View {
        let gpuRows = VisibleMetrics.gpuRows(snapshot.gpu)
        let showCPU = snapshot.cpu != nil
        let showGPU = !gpuRows.isEmpty
        let showMemory = snapshot.memory != nil
        let showDisk = snapshot.disk != nil
        let showNetwork = snapshot.network != nil

        if let cpu = snapshot.cpu {
            cpuGroup(rows: VisibleMetrics.cpuRows(cpu), usage: cpu.usagePercent)
        }
        if showGPU {
            if showCPU { Divider() }
            gpuGroup(rows: gpuRows)
        }
        if let memory = snapshot.memory {
            if showCPU || showGPU { Divider() }
            memoryGroup(rows: VisibleMetrics.memoryRows(memory), memory: memory)
        }
        if let disk = snapshot.disk {
            if showCPU || showGPU || showMemory { Divider() }
            diskGroup(rows: VisibleMetrics.diskRows(disk))
        }
        if let network = snapshot.network {
            if showCPU || showGPU || showMemory || showDisk { Divider() }
            networkGroup(rows: VisibleMetrics.networkRows(network))
        }
        // 整机状态来自非可选字段，始终可见。
        if showCPU || showGPU || showMemory || showDisk || showNetwork { Divider() }
        powerGroup(snapshot)
    }

    @ViewBuilder
    private func rowList(_ rows: [(title: String, value: String)]) -> some View {
        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
            MonitorMetricRow(title: row.title, value: row.value)
        }
    }

    @ViewBuilder
    private func cpuGroup(rows: [(title: String, value: String)], usage: Double?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            MonitorGroupHeader(title: "CPU")
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                MonitorMetricRow(title: row.title, value: row.value)
                // 使用率存在时必为首行，进度条紧随其后。
                if index == 0, let usage {
                    ProgressView(value: min(max(usage, 0), 100), total: 100)
                        .tint(.accentColor)
                        .accessibilityLabel("CPU 使用率")
                        .accessibilityValue(MonitorFormat.percent(usage))
                }
            }
        }
    }

    @ViewBuilder
    private func gpuGroup(rows: [(title: String, value: String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            MonitorGroupHeader(title: "GPU")
            rowList(rows)
        }
    }

    @ViewBuilder
    private func memoryGroup(rows: [(title: String, value: String)], memory: MemoryStats) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            MonitorGroupHeader(title: "内存")
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                MonitorMetricRow(title: row.title, value: row.value)
                if index == 0 {
                    let usedRatio = memory.totalBytes > 0
                        ? Double(memory.usedBytes) / Double(memory.totalBytes)
                        : 0
                    ProgressView(value: min(max(usedRatio, 0), 1))
                        .tint(.accentColor)
                        .accessibilityLabel("内存使用")
                        .accessibilityValue(MonitorFormat.percent(usedRatio * 100))
                }
            }
            if memory.pressure != .unknown {
                MonitorMetricRow(title: "内存压力", value: pressureLabel(memory.pressure), valueColor: pressureColor(memory.pressure))
            }
        }
    }

    @ViewBuilder
    private func diskGroup(rows: [(title: String, value: String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            MonitorGroupHeader(title: "磁盘")
            rowList(rows)
        }
    }

    @ViewBuilder
    private func networkGroup(rows: [(title: String, value: String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            MonitorGroupHeader(title: "网络")
            rowList(rows)
        }
    }

    @ViewBuilder
    private func powerGroup(_ snapshot: SystemSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            MonitorGroupHeader(title: "整机状态")
            if let uptime = VisibleMetrics.uptimeLabel(snapshot.uptimeSeconds) {
                MonitorMetricRow(title: "运行时间", value: uptime)
            }
            if snapshot.thermalState != .unknown {
                MonitorMetricRow(title: "热状态", value: thermalLabel(snapshot.thermalState), valueColor: thermalColor(snapshot.thermalState))
            }
            MonitorMetricRow(
                title: "低功耗模式",
                value: snapshot.isLowPowerModeEnabled ? "已开启" : "已关闭"
            )
        }
    }
}

// MARK: - 设备页

@MainActor
struct DevicesSection: View {
    let snapshot: DeviceSnapshot?
    let isReading: Bool
    let refresh: () -> Void

    // DeviceReadStatus 未来可能新增 case，这里不用穷尽 switch：
    // 已知状态用 if case 匹配，未知状态落入最后的兜底分支，直接展示描述与 message。

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 头部：标题 + 状态（刷新按钮由面板底部统一提供）
            HStack(alignment: .firstTextBaseline) {
                Text("设备").font(.headline)
                Spacer()
                if isReading {
                    Text("读取中…").font(.system(size: 10)).foregroundStyle(.secondary)
                } else if let snapshot {
                    HStack(spacing: 4) {
                        Text("更新于")
                        Text(snapshot.capturedAt, style: .time).monospacedDigit()
                    }
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                // 刷新按钮由面板底部统一提供，这里只保留状态文案；refresh 闭包接口保留。
            }

            if let snapshot {
                statusContent(snapshot)
            } else {
                Text("尚未读取。进入设备页或点击刷新时读取，不在后台循环。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            Text(VisibleMetrics.deviceNote)
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func statusContent(_ snapshot: DeviceSnapshot) -> some View {
        if case .available = snapshot.status {
            if snapshot.devices.isEmpty {
                emptyDevicesBlock(note: "接口可用，但当前没有检测到设备。")
            } else {
                // 有设备时只展示实际读到的值；诊断部分失败不作为整体失败提示。
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(snapshot.devices, id: \.id) { device in
                        deviceCard(device)
                    }
                }
            }
        } else if case .noDevice = snapshot.status {
            emptyDevicesBlock(note: "没有检测到已连接的 iPhone 或 iPad。")
        } else if case .requiresUnlockAndTrust = snapshot.status {
            VStack(alignment: .leading, spacing: 8) {
                MonitorMetricRow(title: "状态", value: "需要解锁并信任", valueColor: .orange)
                guideSteps(steps: [
                    "保持 USB 连接，解锁 iPhone / iPad。",
                    "在设备上确认“信任此电脑”（由你手动确认，本应用不会替你配对）。",
                    "点击面板底部的“刷新”重新读取。",
                ])
            }
        } else if case .unavailable = snapshot.status {
            VStack(alignment: .leading, spacing: 8) {
                MonitorMetricRow(title: "状态", value: "系统接口不可用", valueColor: .orange)
                Text(snapshot.message.isEmpty
                     ? "当前系统没有提供读取外接设备的接口，无法列出设备。"
                     : snapshot.message)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if case .timedOut = snapshot.status {
            VStack(alignment: .leading, spacing: 8) {
                MonitorMetricRow(title: "状态", value: "读取超时", valueColor: .orange)
                Text("设备没有在限定时间内响应。请确认设备已解锁并保持连接，然后点击“刷新”重试。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            // 未来新增的状态：不猜测含义，直接展示。
            VStack(alignment: .leading, spacing: 8) {
                MonitorMetricRow(title: "状态", value: String(describing: snapshot.status))
                if !snapshot.message.isEmpty {
                    Text(snapshot.message)
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private func emptyDevicesBlock(note: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            MonitorMetricRow(title: "状态", value: "未连接设备")
            Text(note)
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            guideSteps(steps: [
                "用 USB 数据线连接 iPhone / iPad（无线连接不在支持范围内）。",
                "解锁设备，并在设备上自行确认“信任此电脑”。",
                "点击面板底部的“刷新”。",
            ])
        }
    }

    @ViewBuilder
    private func guideSteps(steps: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(index + 1).").monospacedDigit()
                    Text(step).fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
        }
    }

    /// 设备卡片只渲染实际读到的值：行列表由 VisibleMetrics.deviceRows 给出，
    /// nil 字段不出现；不显示详细来源路径与缺失字段解释。
    private func deviceCard(_ device: ConnectedDeviceSnapshot) -> some View {
        let rows = VisibleMetrics.deviceRows(device)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                // kind 只有 iPhone / iPad 两种，直接显示；型号可能取不到。
                Text(device.kind.rawValue)
                    .font(.system(size: 12, weight: .semibold))
                if let productType = device.productType, !productType.isEmpty {
                    Text(productType)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let percentage = device.batteryPercentage {
                    Text("\(percentage)%")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .monospacedDigit()
                }
            }
            if let percentage = device.batteryPercentage {
                ProgressView(value: Double(percentage), total: 100)
                    .tint(percentage <= 20 ? .orange : .green)
                    .accessibilityLabel("设备电量")
                    .accessibilityValue("\(percentage)%")
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                MonitorMetricRow(title: row.title, value: row.value)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}
