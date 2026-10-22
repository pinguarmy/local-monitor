// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LocalMonitor",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "LocalMonitor", targets: ["LocalMonitor"]),
        .executable(name: "local-monitor-cli", targets: ["MonitorCLI"])
    ],
    targets: [
        .target(name: "BatteryCore", linkerSettings: [.linkedFramework("IOKit")]),
        .target(name: "SystemCore", linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("Metal")]),
        .target(name: "DeviceCore"),
        .executableTarget(name: "MonitorCLI", dependencies: ["BatteryCore", "SystemCore", "DeviceCore"]),
        .executableTarget(name: "LocalMonitor", dependencies: ["BatteryCore", "SystemCore", "DeviceCore"], linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("SwiftUI")]),
        .testTarget(name: "BatteryCoreTests", dependencies: ["BatteryCore"], exclude: ["StandaloneRunner.swift"]),
        .testTarget(name: "SystemCoreTests", dependencies: ["SystemCore"], exclude: ["StandaloneRunner.swift"]),
        .testTarget(name: "DeviceCoreTests", dependencies: ["DeviceCore"], exclude: ["StandaloneRunner.swift"])
    ]
)
