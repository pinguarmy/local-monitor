import Foundation
import BatteryCore
import SystemCore
import DeviceCore
import Darwin

private struct MachineSnapshot: Codable {
    let battery: BatterySnapshot
    let system: SystemSnapshot
}

@main
struct MonitorCLI {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        do {
            switch arguments {
            case ["--help"]:
                print("""
                Usage: local-monitor-cli [--battery | --system | --devices | --all | --help]
                Default/--battery: one event-independent read-only battery snapshot.
                --system: CPU/GPU/memory/disk/network snapshot with a single 1s baseline interval.
                --devices: one local iPhone/iPad query, no pairing or user-content reads.
                --all: Mac battery and system snapshot; does not query mobile devices.
                No charging controls, root access, SMC writes, history database or telemetry.
                Unknown values are omitted. Dates use ISO 8601.
                Exit: 0 snapshot/no device, 1 encoding error, 2 invalid arguments,
                      3 battery availability unknown, 4 device interface unavailable/timeout.
                """)
            case [], ["--battery"]:
                let battery = BatteryReader().read()
                try output(battery)
                if battery.availability == .unknown { exit(3) }
            case ["--system"], ["--all"]:
                let reader = SystemReader()
                _ = reader.read()
                try await Task.sleep(nanoseconds: 1_000_000_000)
                let system = reader.read()
                if arguments == ["--all"] { try output(MachineSnapshot(battery: BatteryReader().read(), system: system)) }
                else { try output(system) }
            case ["--devices"]:
                let devices = await DeviceReader().read(timeout: 5)
                try output(devices)
                if ["unavailable", "timedOut"].contains(devices.status.rawValue) { exit(4) }
            default:
                FileHandle.standardError.write(Data("Unsupported arguments. Use --help.\n".utf8))
                exit(2)
            }
        } catch {
            FileHandle.standardError.write(Data("Could not produce monitoring snapshot: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    private static func output<T: Encodable>(_ snapshot: T) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var output = try encoder.encode(snapshot)
        output.append(0x0A)
        FileHandle.standardOutput.write(output)
    }
}
