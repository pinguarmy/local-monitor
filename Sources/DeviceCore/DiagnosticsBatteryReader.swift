import Foundation
import CoreFoundation
import Darwin

/// Read-only battery diagnostics over the existing trusted session.
/// Starts com.apple.mobile.diagnostics_relay and sends exactly one fixed narrow query:
///   {"Request":"IORegistry","EntryName":"AppleSmartBatteryPack"}
/// Wire format is the lockdown plist framing: 4-byte big-endian length + XML plist.
/// Values are read ONLY from the explicit path Diagnostics.IORegistry.BatteryData —
/// no recursion, no plane walks, no other keys. This selected source carries Temperature in
/// centi-degrees Celsius and DesignCapacity/NominalChargeCapacity/AppleRawMaxCapacity
/// in mAh, unlike the AppleSmartBattery class entry whose top-level MaxCapacity /
/// FullChargeCapacity are percentages. Any failure degrades to .failed and never
/// affects the basic battery reading.
///
/// Protocol sources (open source only):
///   - libimobiledevice src/diagnostics_relay.c: request keys (EntryName/EntryClass),
///     Status/Diagnostics envelope.
///   - libimobiledevice property_list_service: 4-byte BE length + XML plist framing.
///   - DerekSelander/mobdevim ExternalDeclarations.h: AMDeviceSecureStartService / AMDServiceConnection* ABI.
///   - facebook/idb, troybowman/ios_instruments_client: AMDServiceConnectionSend/Receive return
///     bytes transferred (negative on error), not status codes.
///   - exelban/stats Modules/Battery/readers.swift: same BatteryData.Temperature centi-C
///     and AppleRawMaxCapacity/NominalChargeCapacity mAh semantics on macOS packs.
enum DiagnosticsBatteryReader {
    static let serviceName = "com.apple.mobile.diagnostics_relay"
    static let maxPayloadBytes = 262_144
    /// Numeric keys read from the explicit BatteryData dictionary. Everything else in the
    /// response is never copied. Raw values keep their on-device units; conversion and
    /// range validation happen in DeviceDecoder.
    static let packKeys: Set<String> = ["Temperature", "VirtualTemperature", "DesignCapacity",
                                        "NominalChargeCapacity", "AppleRawMaxCapacity", "CycleCount"]

    static func read(device: UnsafeMutableRawPointer, library: MobileDeviceLibrary,
                     deadline: TimeInterval, progress: DeviceReadProgress) -> BatteryDiagnostics {
        guard let secureStartService = library.secureStartService,
              let connSend = library.connSend,
              let connReceive = library.connReceive,
              let connInvalidate = library.connInvalidate else { return .notAttempted }
        guard !progress.isCancelled, ProcessInfo.processInfo.systemUptime < deadline else { return .failed }

        var connection: UnsafeMutableRawPointer?
        guard secureStartService(device, serviceName as CFString, nil, &connection) == 0,
              let connection else { return .failed }
        defer { connInvalidate(connection) }

        // Bound raw socket reads and writes; the process-level gate still covers any SSL-layer hang.
        if let sock = library.connGetSocket?(connection), sock >= 0 {
            var tv = timeval(tv_sec: 0, tv_usec: 400_000)
            withUnsafeBytes(of: &tv) {
                setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, $0.baseAddress, socklen_t(MemoryLayout<timeval>.size))
                setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, $0.baseAddress, socklen_t(MemoryLayout<timeval>.size))
            }
        }

        guard let response = exchange(connection: connection,
                                      send: connSend, receive: connReceive,
                                      request: ["Request": "IORegistry", "EntryName": "AppleSmartBatteryPack"],
                                      deadline: deadline, progress: progress) else { return .failed }
        guard (response["Status"] as? String) == "Success" else { return .failed }
        let values = extractPackValues(response: response)
        return values.isEmpty ? .failed : .values(values)
    }

    /// Copies whitelisted numeric scalars from the explicit Diagnostics.IORegistry.BatteryData
    /// path only. Top-level lookalikes (MaxCapacity/FullChargeCapacity percentages, temperature
    /// keys outside BatteryData) are never read. Separated from transport for fixture testing.
    static func extractPackValues(response: [String: Any]) -> [String: NSNumber] {
        guard let diagnostics = response["Diagnostics"] as? [String: Any],
              let registry = diagnostics["IORegistry"] as? [String: Any],
              let batteryData = registry["BatteryData"] as? [String: Any] else { return [:] }
        var values: [String: NSNumber] = [:]
        for key in packKeys {
            if let number = batteryData[key] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
                values[key] = number
            }
        }
        return values
    }

    private static func exchange(connection: UnsafeMutableRawPointer,
                                 send: MobileDeviceLibrary.ConnSend,
                                 receive: MobileDeviceLibrary.ConnReceive,
                                 request: [String: Any],
                                 deadline: TimeInterval, progress: DeviceReadProgress) -> [String: Any]? {
        guard let body = try? PropertyListSerialization.data(fromPropertyList: request, format: .xml, options: 0) else { return nil }
        var header = UInt32(body.count).bigEndian
        let sentHeader = withUnsafeBytes(of: &header) { sendAll(connection, send, $0.baseAddress!, 4, deadline, progress) }
        guard sentHeader else { return nil }
        let sentBody = body.withUnsafeBytes { buffer -> Bool in
            guard let base = buffer.baseAddress else { return false }
            return sendAll(connection, send, base, buffer.count, deadline, progress)
        }
        guard sentBody else { return nil }
        guard let headerData = recvExact(connection, receive, 4, deadline, progress) else { return nil }
        // Manual big-endian decode: Data bytes are not guaranteed aligned for load(as:).
        let length = headerData.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard length > 0, Int(length) <= maxPayloadBytes else { return nil }
        guard let payload = recvExact(connection, receive, Int(length), deadline, progress),
              let object = try? PropertyListSerialization.propertyList(from: payload, format: nil),
              let dict = object as? [String: Any] else { return nil }
        return dict
    }

    /// Byte-counting semantics: returns bytes written, negative on error. Loop partial writes.
    private static func sendAll(_ connection: UnsafeMutableRawPointer,
                                _ send: MobileDeviceLibrary.ConnSend,
                                _ bytes: UnsafeRawPointer, _ count: Int,
                                _ deadline: TimeInterval, _ progress: DeviceReadProgress) -> Bool {
        var sent = 0
        while sent < count {
            guard !progress.isCancelled, ProcessInfo.processInfo.systemUptime < deadline else { return false }
            let n = send(connection, bytes.advanced(by: sent), count - sent)
            guard n > 0, n <= count - sent else { return false }
            sent += n
        }
        return true
    }

    private static func recvExact(_ connection: UnsafeMutableRawPointer,
                                  _ receive: MobileDeviceLibrary.ConnReceive,
                                  _ count: Int,
                                  _ deadline: TimeInterval, _ progress: DeviceReadProgress) -> Data? {
        var data = Data(count: count)
        var received = 0
        while received < count {
            guard !progress.isCancelled, ProcessInfo.processInfo.systemUptime < deadline else { return nil }
            let n = data.withUnsafeMutableBytes { buffer -> Int in
                receive(connection, buffer.baseAddress!.advanced(by: received), count - received)
            }
            guard n > 0, n <= count - received else { return nil }
            received += n
        }
        return data
    }
}
