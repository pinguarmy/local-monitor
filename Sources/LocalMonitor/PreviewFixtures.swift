import Foundation
import BatteryCore
import SystemCore
import DeviceCore

/// Built-in representative data for `--render-preview --preview-fixture`, so CI runners without
/// a battery or a connected iPhone still render the populated tabs. Never used in normal runs.
enum PreviewFixtures {
    /// A present, discharging battery with time remaining, health and electrical rows and both footnotes.
    static var battery: BatterySnapshot {
        BatterySnapshot(
            isPresent: true, percentage: 72, powerSource: "Battery Power", isCharging: false, isCharged: false,
            condition: "Good", maximumCapacityMAh: 4210, designCapacityMAh: 4382, healthPercent: 96.1, cycleCount: 187,
            temperatureCelsius: 30.4, voltageVolts: 12.512, amperageMA: -1180, powerWatts: -14.76,
            timeToEmptyMinutes: 263
        )
    }

    /// One iPhone with full details and one iPad with only basic values (unknown model identifier).
    static var devices: DeviceSnapshot {
        DeviceSnapshot(
            status: .available,
            devices: [
                ConnectedDeviceSnapshot(
                    id: "0", productType: "iPhone16,1", productVersion: "18.1", kind: .iPhone,
                    batteryPercentage: 76, chargingState: .charging, externalPowerConnected: true,
                    temperatureCelsius: 29.5, cycleCount: 312, designCapacityMAh: 3274, fullChargeCapacityMAh: 2980,
                    batteryDetailsStatus: "available"),
                ConnectedDeviceSnapshot(id: "1", productType: "iPad13,18", productVersion: "18.1", kind: .iPad,
                                        batteryPercentage: 54),
            ],
            frameworkLoaded: true,
            message: "Preview fixture"
        )
    }

    /// A fully sampled system snapshot (CPU usage and network rates included).
    static var system: SystemSnapshot {
        let gib: UInt64 = 1024 * 1024 * 1024
        return SystemSnapshot(
            timestamp: Date(),
            cpu: CPUStats(logicalCoreCount: 10, physicalCoreCount: 10, usagePercent: 23.4,
                          loadAverage1: 2.31, loadAverage5: 2.05, loadAverage15: 1.87),
            gpu: GPUStats(name: "Apple M2 Pro", utilizationPercent: 12),
            memory: MemoryStats(totalBytes: 16 * gib, usedBytes: 10 * gib, availableBytes: 6 * gib,
                                compressedBytes: 2 * gib, swapUsedBytes: gib / 2, pressure: .normal),
            disk: DiskStats(totalBytes: 460 * gib, freeBytes: 190 * gib, availableBytes: 180 * gib),
            network: NetworkStats(receivedBytes: 8 * gib, sentBytes: gib, downloadBytesPerSecond: 1_250_000,
                                  uploadBytesPerSecond: 86_000, intervalSeconds: 2),
            thermalState: .nominal, isLowPowerModeEnabled: false, uptimeSeconds: 3 * 86_400 + 4 * 3600,
            limitations: []
        )
    }
}
