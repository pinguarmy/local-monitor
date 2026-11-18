import Foundation
import BatteryCore
import SystemCore
import DeviceCore

/// What the Devices tab shows instead of device cards: a status row, an optional
/// explanation and optional numbered steps. Derived from `status` + `issue` only;
/// `DeviceSnapshot.message` is CLI diagnostics and never reaches the UI.
struct DeviceStatusDisplay: Equatable {
    let status: String
    let tone: MetricTone
    let detail: String?
    let steps: [String]
}

/// Pure visible-metric rules shared by the views and the LocalMonitorTests checks.
/// Only metrics that were actually read produce rows. Nil values are omitted, never
/// replaced by "not sampled" / "unavailable" placeholders.
enum VisibleMetrics {
    /// Fixed note at the bottom of the Devices tab: read-only and what the numbering means.
    static var deviceNote: String { L10n.deviceNote }

    static func uptimeLabel(_ seconds: Double) -> String? { MonitorFormat.uptime(seconds) }

    static func chargingLabel(_ state: DeviceChargingState) -> String { L10n.chargingState(state) }

    // MARK: System tab

    /// The first frame has no delta baseline, so the usage row is absent while usagePercent is nil.
    /// Load lists only the sampled windows; the row disappears when none were read.
    static func cpuRows(_ cpu: CPUStats?) -> [MetricItem] {
        guard let cpu else { return [] }
        var rows: [MetricItem] = []
        if let usage = cpu.usagePercent {
            rows.append(MetricItem(title: L10n.cpuUsage, value: MonitorFormat.percent(usage)))
        }
        rows.append(MetricItem(title: L10n.cpuCores,
                               value: L10n.coreCounts(logical: cpu.logicalCoreCount, physical: cpu.physicalCoreCount)))
        var loads: [(minutes: Int, value: String)] = []
        if let load = cpu.loadAverage1 { loads.append((minutes: 1, value: MonitorFormat.loadAverage(load))) }
        if let load = cpu.loadAverage5 { loads.append((minutes: 5, value: MonitorFormat.loadAverage(load))) }
        if let load = cpu.loadAverage15 { loads.append((minutes: 15, value: MonitorFormat.loadAverage(load))) }
        if !loads.isEmpty {
            rows.append(MetricItem(title: L10n.cpuLoad, value: L10n.loadAverages(loads)))
        }
        return rows
    }

    /// Present only together with the usage row, which is then the first row.
    static func cpuGauge(_ cpu: CPUStats?) -> MetricGauge? {
        guard let usage = cpu?.usagePercent, usage.isFinite else { return nil }
        return MetricGauge(fraction: usage / 100, spokenLabel: L10n.cpuUsageAccessibility,
                           spokenValue: MonitorFormat.percent(usage))
    }

    /// GPU utilization is often not exposed; then only the model row remains.
    static func gpuRows(_ gpu: GPUStats?) -> [MetricItem] {
        guard let gpu else { return [] }
        var rows: [MetricItem] = []
        if let name = gpu.name, !name.isEmpty {
            rows.append(MetricItem(title: L10n.gpuModel, value: name))
        }
        if let utilization = gpu.utilizationPercent {
            rows.append(MetricItem(title: L10n.gpuUtilization, value: MonitorFormat.percent(utilization)))
        }
        return rows
    }

    /// Swap is hidden when not read; pressure is hidden when the kernel level is unknown.
    static func memoryRows(_ memory: MemoryStats?) -> [MetricItem] {
        guard let memory else { return [] }
        var rows: [MetricItem] = [
            MetricItem(title: L10n.usedOfTotal,
                       value: L10n.pair(MonitorFormat.bytes(memory.usedBytes), MonitorFormat.bytes(memory.totalBytes))),
            MetricItem(title: L10n.available, value: MonitorFormat.bytes(memory.availableBytes)),
            MetricItem(title: L10n.compressed, value: MonitorFormat.bytes(memory.compressedBytes)),
        ]
        if let swap = memory.swapUsedBytes {
            rows.append(MetricItem(title: L10n.swap, value: MonitorFormat.bytes(swap)))
        }
        if memory.pressure != .unknown {
            rows.append(MetricItem(title: L10n.memoryPressure, value: L10n.memoryPressureLevel(memory.pressure),
                                   tone: pressureTone(memory.pressure)))
        }
        return rows
    }

    static func memoryGauge(_ memory: MemoryStats?) -> MetricGauge? {
        guard let memory else { return nil }
        return usageGauge(used: memory.usedBytes, total: memory.totalBytes, spokenLabel: L10n.memoryUsageAccessibility)
    }

    /// Used = total − available to unprivileged processes (saturating), so reserved blocks count
    /// as used. Finder also counts purgeable space as available, so its figure can be lower.
    static func diskUsedBytes(_ disk: DiskStats) -> UInt64 {
        disk.totalBytes > disk.availableBytes ? disk.totalBytes - disk.availableBytes : 0
    }

    static func diskRows(_ disk: DiskStats?) -> [MetricItem] {
        guard let disk else { return [] }
        return [
            MetricItem(title: L10n.usedOfTotal,
                       value: L10n.pair(MonitorFormat.bytes(diskUsedBytes(disk)), MonitorFormat.bytes(disk.totalBytes))),
            MetricItem(title: L10n.available, value: MonitorFormat.bytes(disk.availableBytes)),
        ]
    }

    static func diskGauge(_ disk: DiskStats?) -> MetricGauge? {
        guard let disk else { return nil }
        return usageGauge(used: diskUsedBytes(disk), total: disk.totalBytes, spokenLabel: L10n.diskUsageAccessibility)
    }

    /// Rates need two samples of the same interfaces; they stay hidden until then.
    static func networkRows(_ network: NetworkStats?) -> [MetricItem] {
        guard let network else { return [] }
        var rows: [MetricItem] = []
        if let download = network.downloadBytesPerSecond {
            rows.append(MetricItem(title: L10n.download, value: MonitorFormat.bytesPerSecond(download)))
        }
        if let upload = network.uploadBytesPerSecond {
            rows.append(MetricItem(title: L10n.upload, value: MonitorFormat.bytesPerSecond(upload)))
        }
        rows.append(MetricItem(title: L10n.receivedSent,
                               value: L10n.pair(MonitorFormat.bytes(network.receivedBytes), MonitorFormat.bytes(network.sentBytes))))
        return rows
    }

    /// Uptime, thermal state (hidden when unknown) and Low Power Mode, which is always known.
    static func machineRows(_ snapshot: SystemSnapshot) -> [MetricItem] {
        var rows: [MetricItem] = []
        if let uptime = uptimeLabel(snapshot.uptimeSeconds) {
            rows.append(MetricItem(title: L10n.uptime, value: uptime))
        }
        if snapshot.thermalState != .unknown {
            rows.append(MetricItem(title: L10n.thermalState, value: L10n.thermalLevel(snapshot.thermalState),
                                   tone: thermalTone(snapshot.thermalState)))
        }
        rows.append(MetricItem(title: L10n.lowPowerMode, value: L10n.onOff(snapshot.isLowPowerModeEnabled)))
        return rows
    }

    static func thermalTone(_ state: ThermalState) -> MetricTone {
        switch state {
        case .nominal, .unknown: return .normal
        case .fair: return .warning
        case .serious, .critical: return .critical
        }
    }

    static func pressureTone(_ pressure: MemoryPressure) -> MetricTone {
        switch pressure {
        case .normal, .unknown: return .normal
        case .warning: return .warning
        case .critical: return .critical
        }
    }

    private static func usageGauge(used: UInt64, total: UInt64, spokenLabel: String) -> MetricGauge? {
        guard total > 0 else { return nil }
        let fraction = min(max(Double(used) / Double(total), 0), 1)
        return MetricGauge(fraction: fraction, spokenLabel: spokenLabel, spokenValue: MonitorFormat.percent(fraction * 100))
    }

    // MARK: Battery tab (rows exist only for a present battery)

    /// Time remaining, time until full and adapter wattage. Non-positive values are treated as unavailable.
    static func batteryChargeRows(_ snapshot: BatterySnapshot) -> [MetricItem] {
        guard snapshot.availability == .present else { return [] }
        var rows: [MetricItem] = []
        if let minutes = snapshot.timeToEmptyMinutes, let text = MonitorFormat.duration(minutes: minutes) {
            rows.append(MetricItem(title: L10n.timeRemaining, value: text))
        }
        if let minutes = snapshot.timeToFullChargeMinutes, let text = MonitorFormat.duration(minutes: minutes) {
            rows.append(MetricItem(title: L10n.timeToFull, value: text))
        }
        if let watts = snapshot.adapterWatts, watts > 0 {
            rows.append(MetricItem(title: L10n.powerAdapter, value: MonitorFormat.watts(watts)))
        }
        return rows
    }

    static func batteryHealthRows(_ snapshot: BatterySnapshot) -> [MetricItem] {
        guard snapshot.availability == .present else { return [] }
        var rows: [MetricItem] = []
        if let condition = snapshot.condition, !condition.isEmpty {
            rows.append(MetricItem(title: L10n.batteryCondition, value: condition))
        }
        if let reported = snapshot.reportedHealthPercent {
            rows.append(MetricItem(title: L10n.batteryReportedMaximum, value: MonitorFormat.roundedPercent(reported)))
        }
        if let health = snapshot.healthPercent {
            rows.append(MetricItem(title: L10n.batteryCapacityRatio, value: MonitorFormat.percent(health)))
        }
        if let maximum = snapshot.maximumCapacityMAh {
            rows.append(MetricItem(title: L10n.batteryFullChargeCapacity, value: MonitorFormat.milliampHours(maximum)))
        }
        if let design = snapshot.designCapacityMAh {
            rows.append(MetricItem(title: L10n.designCapacity, value: MonitorFormat.milliampHours(design)))
        }
        if let cycles = snapshot.cycleCount {
            rows.append(MetricItem(title: L10n.cycleCount, value: String(cycles)))
        }
        return rows
    }

    static func batteryElectricalRows(_ snapshot: BatterySnapshot) -> [MetricItem] {
        guard snapshot.availability == .present else { return [] }
        var rows: [MetricItem] = []
        if let temperature = snapshot.temperatureCelsius {
            rows.append(MetricItem(title: L10n.batteryTemperature, value: MonitorFormat.celsius(temperature)))
        }
        if let voltage = snapshot.voltageVolts {
            rows.append(MetricItem(title: L10n.voltage, value: MonitorFormat.volts(voltage)))
        }
        if let current = snapshot.amperageMA {
            rows.append(MetricItem(title: L10n.current, value: MonitorFormat.milliamps(current)))
        }
        if let power = snapshot.powerWatts {
            rows.append(MetricItem(title: L10n.batteryPower, value: MonitorFormat.signedWatts(power)))
        }
        return rows
    }

    /// Footnotes explain only rows that are actually shown.
    static func batteryFootnotes(_ snapshot: BatterySnapshot) -> [String] {
        var notes: [String] = []
        if batteryElectricalRows(snapshot).contains(where: { $0.title == L10n.batteryPower }) {
            notes.append(L10n.batteryPowerFootnote)
        }
        if batteryHealthRows(snapshot).contains(where: { $0.title == L10n.batteryCapacityRatio }) {
            notes.append(L10n.capacityRatioFootnote)
        }
        return notes
    }

    // MARK: Devices tab

    /// Only values actually read. Source paths, batteryDetailsStatus and `message` never become rows;
    /// a partial diagnostics failure is not treated as a failed card.
    static func deviceRows(_ device: ConnectedDeviceSnapshot) -> [MetricItem] {
        var rows: [MetricItem] = []
        if let version = device.productVersion, !version.isEmpty {
            rows.append(MetricItem(title: L10n.osVersion, value: L10n.osVersionValue(kind: device.kind, version: version)))
        }
        if let state = device.chargingState {
            rows.append(MetricItem(title: L10n.chargingStatus, value: chargingLabel(state)))
        }
        if let external = device.externalPowerConnected {
            rows.append(MetricItem(title: L10n.externalPower, value: L10n.connected(external)))
        }
        if let temperature = device.temperatureCelsius {
            rows.append(MetricItem(title: L10n.batteryTemperature, value: MonitorFormat.celsius(temperature)))
        }
        if let cycles = device.cycleCount {
            rows.append(MetricItem(title: L10n.cycleCount, value: String(cycles)))
        }
        if let full = device.fullChargeCapacityMAh {
            rows.append(MetricItem(title: L10n.deviceFullChargeCapacity, value: MonitorFormat.milliampHours(full)))
        }
        if let design = device.designCapacityMAh {
            rows.append(MetricItem(title: L10n.designCapacity, value: MonitorFormat.milliampHours(design)))
        }
        if let full = device.fullChargeCapacityMAh, let design = device.designCapacityMAh, design > 0 {
            rows.append(MetricItem(title: L10n.deviceCapacityRatio,
                                   value: MonitorFormat.percent(Double(full) / Double(design) * 100)))
        }
        return rows
    }

    static var connectSteps: [String] {
        [L10n.stepConnectCable, L10n.stepUnlockAndTrustYourself, L10n.stepClickRefresh]
    }

    static var unlockSteps: [String] {
        [L10n.stepKeepConnectedAndUnlock, L10n.stepConfirmTrust, L10n.stepClickRefresh]
    }

    /// Nil when device cards should be shown instead (available with at least one device).
    /// An issue sentence, when present, replaces the status's default explanation.
    static func deviceStatus(_ snapshot: DeviceSnapshot) -> DeviceStatusDisplay? {
        let issueText: String? = snapshot.issue.map { L10n.deviceIssue($0) }
        switch snapshot.status {
        case .available:
            guard snapshot.devices.isEmpty else { return nil }
            return DeviceStatusDisplay(status: L10n.noDeviceConnected, tone: issueText == nil ? .normal : .warning,
                                       detail: issueText ?? L10n.availableButEmptyDetail, steps: connectSteps)
        case .noDevice:
            return DeviceStatusDisplay(status: L10n.noDeviceConnected, tone: issueText == nil ? .normal : .warning,
                                       detail: issueText ?? L10n.noDeviceDetail, steps: connectSteps)
        case .requiresUnlockAndTrust:
            return DeviceStatusDisplay(status: L10n.unlockAndTrustRequired, tone: .warning,
                                       detail: issueText, steps: unlockSteps)
        case .unavailable:
            return DeviceStatusDisplay(status: L10n.interfaceUnavailable, tone: .warning,
                                       detail: issueText ?? L10n.unavailableDetail, steps: [])
        case .timedOut:
            return DeviceStatusDisplay(status: L10n.readTimedOut, tone: .warning,
                                       detail: issueText ?? L10n.timedOutDetail, steps: [])
        }
    }

    /// An issue reported alongside device cards (e.g. one device unreadable), shown under the cards.
    static func deviceIssueNote(_ snapshot: DeviceSnapshot) -> String? {
        guard deviceStatus(snapshot) == nil, let issue = snapshot.issue else { return nil }
        return L10n.deviceIssue(issue)
    }
}
