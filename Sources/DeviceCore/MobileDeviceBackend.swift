import Foundation
import CoreFoundation
import Darwin

/// Every MobileDevice symbol is resolved at runtime. There is no linker dependency on the private framework.
///
/// What this module reads, and nothing else:
///   - device attach/detach notifications (opaque handle + event code only, never am_device fields);
///   - the transport of each handle via AMDeviceGetInterfaceType (optional), so that devices visible
///     only over the network (Wi-Fi sync) are skipped and never queried — only USB devices are read;
///   - after an existing pairing is confirmed (never created), individual allowlisted lockdown keys:
///     ProductType, ProductVersion, DeviceClass and four com.apple.mobile.battery keys;
///   - one fixed diagnostics_relay battery query (see DiagnosticsBatteryReader).
/// No UDID, serial number, device name or pairing record is ever requested.
final class MobileDeviceLibrary {
    typealias DeviceCall = @convention(c) (UnsafeMutableRawPointer?) -> Int32
    typealias DeviceLifetime = @convention(c) (UnsafeMutableRawPointer?) -> Void
    typealias Callback = @convention(c) (UnsafeRawPointer?, UnsafeMutableRawPointer?) -> Void
    typealias Subscribe = @convention(c) (Callback?, UInt32, UInt32, UnsafeMutableRawPointer?, UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32
    typealias CopyValue = @convention(c) (UnsafeMutableRawPointer?, CFString?, CFString?) -> Unmanaged<CFTypeRef>?
    typealias Unsubscribe = @convention(c) (UnsafeMutableRawPointer?) -> Int32
    // Optional diagnostics transport. Absence degrades battery details to nil, never to failure.
    typealias SecureStartService = @convention(c) (UnsafeMutableRawPointer?, CFString?, CFDictionary?, UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32
    // Byte-counting semantics: bytes transferred, negative on error (facebook/idb, ios_instruments_client).
    typealias ConnSend = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, Int) -> Int
    typealias ConnReceive = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int) -> Int
    typealias ConnInvalidate = @convention(c) (UnsafeMutableRawPointer?) -> Void
    typealias ConnGetSocket = @convention(c) (UnsafeMutableRawPointer?) -> Int32
    // Optional transport query: int AMDeviceGetInterfaceType(AMDeviceRef). Per ios-deploy MobileDevice.h,
    // 1 = USB/wired, 2 = Wi-Fi. Same C shape as DeviceCall. Absence never affects `ready`.
    typealias InterfaceType = DeviceCall

    static let paths = [
        "/Library/Apple/System/Library/PrivateFrameworks/MobileDevice.framework/MobileDevice",
        "/System/Library/PrivateFrameworks/MobileDevice.framework/MobileDevice"
    ]
    let loaded: Bool
    let subscribe: Subscribe?
    let unsubscribe: Unsubscribe?
    let connect: DeviceCall?
    let disconnect: DeviceCall?
    let isPaired: DeviceCall?
    let validatePairing: DeviceCall?
    let startSession: DeviceCall?
    let stopSession: DeviceCall?
    let retainDevice: DeviceLifetime?
    let releaseDevice: DeviceLifetime?
    let copyValue: CopyValue?
    let secureStartService: SecureStartService?
    let connSend: ConnSend?
    let connReceive: ConnReceive?
    let connInvalidate: ConnInvalidate?
    let connGetSocket: ConnGetSocket?
    let interfaceType: InterfaceType?
    // interfaceType is deliberately not required: without it every handle is read as before.
    var ready: Bool {
        loaded && subscribe != nil && unsubscribe != nil && connect != nil && disconnect != nil &&
        isPaired != nil && validatePairing != nil && startSession != nil && stopSession != nil &&
        retainDevice != nil && releaseDevice != nil && copyValue != nil
    }

    init(paths: [String] = MobileDeviceLibrary.paths,
         resolve: (UnsafeMutableRawPointer, String) -> UnsafeMutableRawPointer? = { dlsym($0, $1) }) {
        let handle = paths.lazy.compactMap { dlopen($0, RTLD_LOCAL | RTLD_LAZY) }.first
        loaded = handle != nil
        func symbol<T>(_ name: String, _: T.Type) -> T? {
            guard let handle, let address = resolve(handle, name) else { return nil }
            return unsafeBitCast(address, to: T.self)
        }
        subscribe = symbol("AMDeviceNotificationSubscribe", Subscribe.self)
        unsubscribe = symbol("AMDeviceNotificationUnsubscribe", Unsubscribe.self)
        connect = symbol("AMDeviceConnect", DeviceCall.self)
        disconnect = symbol("AMDeviceDisconnect", DeviceCall.self)
        isPaired = symbol("AMDeviceIsPaired", DeviceCall.self)
        validatePairing = symbol("AMDeviceValidatePairing", DeviceCall.self)
        startSession = symbol("AMDeviceStartSession", DeviceCall.self)
        stopSession = symbol("AMDeviceStopSession", DeviceCall.self)
        retainDevice = symbol("AMDeviceRetain", DeviceLifetime.self)
        releaseDevice = symbol("AMDeviceRelease", DeviceLifetime.self)
        copyValue = symbol("AMDeviceCopyValue", CopyValue.self)
        secureStartService = symbol("AMDeviceSecureStartService", SecureStartService.self)
        connSend = symbol("AMDServiceConnectionSend", ConnSend.self)
        connReceive = symbol("AMDServiceConnectionReceive", ConnReceive.self)
        connInvalidate = symbol("AMDServiceConnectionInvalidate", ConnInvalidate.self)
        connGetSocket = symbol("AMDServiceConnectionGetSocket", ConnGetSocket.self)
        interfaceType = symbol("AMDeviceGetInterfaceType", InterfaceType.self)
        // Keep a successfully loaded private image resident. Its callbacks/CF classes may outlive a read.
        // No error text from dlerror is exposed because framework diagnostics are not our public API.
    }
}

/// Decides when the notification scan may stop. Pure, so it is testable without hardware.
/// The hard end always wins. Before any device is known the scan waits up to the hard end
/// (a first notification can legitimately take a while, so no-device behaviour is unchanged).
/// Once at least one device is known, the scan ends after `quietPeriod` without a new
/// attach/detach event, so a connected device does not cost the full scan window.
enum DeviceScanPolicy {
    static let quietPeriod: TimeInterval = 0.3

    static func shouldKeepWaiting(now: TimeInterval, scanStart: TimeInterval, hardEnd: TimeInterval,
                                  lastEventAt: TimeInterval?, deviceCount: Int,
                                  quietPeriod: TimeInterval = DeviceScanPolicy.quietPeriod) -> Bool {
        guard now < hardEnd else { return false }
        guard deviceCount > 0, let lastEventAt else { return true }
        // Events delivered synchronously during subscribe can predate scanStart; measure the
        // quiet period from whichever is later.
        return now - max(scanStart, lastEventAt) < quietPeriod
    }
}

/// "USB only": a handle is skipped only when the optional transport query reports exactly 2 (Wi-Fi).
/// Any other value, or a missing symbol (nil), reads the device as before.
enum DeviceTransportPolicy {
    static let wifiInterfaceType: Int32 = 2

    static func shouldSkip(interfaceType: Int32?) -> Bool {
        interfaceType == wifiInterfaceType
    }
}

private final class DeviceEnumeration {
    let library: MobileDeviceLibrary
    var handles: [UnsafeMutableRawPointer] = []
    /// systemUptime of the last attach/detach notification; nil until one arrives.
    /// Only touched on the reading thread (callbacks run inside its CFRunLoopRunInMode).
    var lastEventUptime: TimeInterval?
    init(_ library: MobileDeviceLibrary) { self.library = library }
    func receive(_ info: UnsafeRawPointer) {
        // Read only the documented callback prefix: opaque device handle, then uint32 event.
        // Never inspect am_device fields or obtain a persistent device identifier.
        guard let device = info.load(as: UnsafeMutableRawPointer?.self) else { return }
        let event = info.load(fromByteOffset: MemoryLayout<UnsafeMutableRawPointer>.size, as: UInt32.self)
        if event == 1 || event == 2 { lastEventUptime = ProcessInfo.processInfo.systemUptime }
        if event == 1 && !handles.contains(device) {
            library.retainDevice?(device)
            handles.append(device)
        } else if event == 2, let index = handles.firstIndex(of: device) {
            handles.remove(at: index)
            library.releaseDevice?(device)
        }
    }
    deinit { for device in handles { library.releaseDevice?(device) } }
}

private let notificationCallback: MobileDeviceLibrary.Callback = { info, context in
    guard let info, let context else { return }
    Unmanaged<DeviceEnumeration>.fromOpaque(context).takeUnretainedValue().receive(info)
}

enum MobileDeviceBackend {
    private static let library = MobileDeviceLibrary()

    static func read(timeout: TimeInterval, progress: DeviceReadProgress) -> DeviceSnapshot {
        read(library: library, timeout: timeout, progress: progress)
    }

    static func read(library: MobileDeviceLibrary, timeout: TimeInterval,
                     progress: DeviceReadProgress) -> DeviceSnapshot {
        if library.loaded { progress.markLoaded() }
        guard library.ready else {
            return result(.unavailable, library, DeviceMessage.frameworkUnavailable, issue: .frameworkUnavailable)
        }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        let enumeration = DeviceEnumeration(library)
        let context = Unmanaged.passRetained(enumeration)
        var subscription: UnsafeMutableRawPointer?
        let subscribeCode = library.subscribe?(notificationCallback, 0, 0, context.toOpaque(), &subscription) ?? -1
        guard subscribeCode == 0, let subscription else {
            // On a failed subscription the framework must not retain the callback.
            context.release()
            return result(.unavailable, library, DeviceMessage.subscriptionFailed, issue: .subscriptionFailed)
        }
        // A short bounded runloop allows initial connected-device notifications to arrive.
        // No notifications is reported as noDevice, not a successful hardware read.
        // The scan ends early once a device is known and the list has been quiet (DeviceScanPolicy);
        // scanEnd remains the hard cap and cancellation is checked on every slice, as before.
        let scanStart = ProcessInfo.processInfo.systemUptime
        let scanEnd = min(deadline - 0.02, scanStart + min(1.5, timeout * 0.65))
        while !progress.isCancelled {
            let now = ProcessInfo.processInfo.systemUptime
            guard DeviceScanPolicy.shouldKeepWaiting(now: now, scanStart: scanStart, hardEnd: scanEnd,
                                                     lastEventAt: enumeration.lastEventUptime,
                                                     deviceCount: enumeration.handles.count) else { break }
            let remaining = scanEnd - now
            CFRunLoopRunInMode(.defaultMode, min(0.05, max(0, remaining)), false)
        }
        let unsubscribeCode = library.unsubscribe?(subscription) ?? -1
        guard unsubscribeCode == 0 else {
            // Leaking one retained context is safer than a late callback using freed memory.
            // Permanently quarantine the process-wide native gate to prevent repeated leaks.
            progress.quarantine()
            return result(.unavailable, library, DeviceMessage.notificationCleanupFailed,
                          issue: .notificationCleanupFailed)
        }
        context.release()
        // Keep the enumeration (and therefore every retained device handle) alive until the last
        // native call below. Swift may otherwise end its lifetime right after the last direct use
        // (copying `handles`), and its deinit would AMDeviceRelease the handles while they are
        // still being connected to and queried.
        return withExtendedLifetime(enumeration) { () -> DeviceSnapshot in
            guard !progress.isCancelled, ProcessInfo.processInfo.systemUptime < deadline else {
                return result(.timedOut, library, DeviceMessage.timedOut)
            }
            guard !enumeration.handles.isEmpty else {
                return result(.noDevice, library, DeviceMessage.noDevice)
            }
            var devices: [ConnectedDeviceSnapshot] = []
            var failures: [DeviceReadStatus] = []
            var skippedNonUSB = 0
            for handle in enumeration.handles {
                guard !progress.isCancelled, ProcessInfo.processInfo.systemUptime < deadline else {
                    return result(.timedOut, library, DeviceMessage.timedOutDuringRead, devices)
                }
                // USB only: a Wi-Fi-visible handle is skipped (not a failure) and never queried.
                // It may also be a second handle for a phone already enumerated over USB.
                let transport = library.interfaceType.map { $0(handle) }
                if DeviceTransportPolicy.shouldSkip(interfaceType: transport) {
                    skippedNonUSB += 1
                    continue
                }
                switch readDevice(handle, library: library, ordinal: devices.count + 1,
                                  deadline: deadline, progress: progress) {
                case .device(let device): devices.append(device)
                case .failure(let status): failures.append(status)
                case .unsupported: break
                }
            }
            if !devices.isEmpty {
                let message = failures.isEmpty ? DeviceMessage.available : DeviceMessage.partiallyAvailable
                return result(.available, library, message, devices)
            }
            if failures.contains(.requiresUnlockAndTrust) {
                return result(.requiresUnlockAndTrust, library, DeviceMessage.requiresUnlockAndTrust)
            }
            if failures.contains(.timedOut) { return result(.timedOut, library, DeviceMessage.communicationTimedOut) }
            if !failures.isEmpty {
                return result(.unavailable, library, DeviceMessage.deviceUnreadable, issue: .deviceUnreadable)
            }
            if skippedNonUSB == enumeration.handles.count {
                return result(.noDevice, library, DeviceMessage.noUSBDevice)
            }
            return result(.noDevice, library, DeviceMessage.noReadableDevice)
        }
    }

    private enum ReadOutcome {
        case device(ConnectedDeviceSnapshot), failure(DeviceReadStatus), unsupported
    }

    private static func readDevice(_ device: UnsafeMutableRawPointer, library: MobileDeviceLibrary,
                                   ordinal: Int, deadline: TimeInterval, progress: DeviceReadProgress) -> ReadOutcome {
        let connectCode = library.connect?(device) ?? -1
        guard connectCode == 0 else { return .failure(DeviceNativeFailure.status(for: connectCode)) }
        defer { _ = library.disconnect?(device) }
        guard !progress.isCancelled else { return .failure(.timedOut) }
        // IsPaired is the only precondition. Never attempt Pair, Unpair, Trust, activation, or writes.
        guard library.isPaired?(device) == 1 else { return .failure(.requiresUnlockAndTrust) }
        let validateCode = library.validatePairing?(device) ?? -1
        guard validateCode == 0 else { return .failure(DeviceNativeFailure.status(for: validateCode)) }
        guard !progress.isCancelled else { return .failure(.timedOut) }
        let sessionCode = library.startSession?(device) ?? -1
        guard sessionCode == 0 else { return .failure(DeviceNativeFailure.status(for: sessionCode)) }
        defer { _ = library.stopSession?(device) }
        func copy(_ key: String, domain: String? = nil) -> Any? {
            guard !progress.isCancelled else { return nil }
            return library.copyValue?(device, domain.map { $0 as CFString }, key as CFString)?.takeRetainedValue()
        }
        // Query individual keys, never whole root dictionaries or arbitrary domains.
        var product: [String: Any] = [:]
        for key in ["ProductType", "ProductVersion", "DeviceClass"] { product[key] = copy(key) }
        var battery: [String: Any] = [:]
        for key in ["BatteryCurrentCapacity", "BatteryIsCharging", "FullyCharged", "ExternalConnected"] {
            battery[key] = copy(key, domain: "com.apple.mobile.battery")
        }
        guard !progress.isCancelled else { return .failure(.timedOut) }
        // Optional read-only diagnostics enrichment with its own tighter deadline to reserve
        // margin for the basic reading (min(global-0.5s, now+1s)). A hang inside the private
        // framework itself still cannot be bounded by this margin; see README risk notes.
        var diagnostics: BatteryDiagnostics = .notAttempted
        let diagDeadline = min(deadline - 0.5, ProcessInfo.processInfo.systemUptime + 1.0)
        if ProcessInfo.processInfo.systemUptime < diagDeadline {
            diagnostics = DiagnosticsBatteryReader.read(device: device, library: library,
                                                        deadline: diagDeadline, progress: progress)
        }
        guard !progress.isCancelled else { return .failure(.timedOut) }
        guard let decoded = DeviceDecoder.decode(product: product, battery: battery,
                                                 diagnostics: diagnostics, ordinal: ordinal) else {
            return product.isEmpty ? .failure(.unavailable) : .unsupported
        }
        return .device(decoded)
    }

    private static func result(_ status: DeviceReadStatus, _ library: MobileDeviceLibrary,
                               _ message: String, _ devices: [ConnectedDeviceSnapshot] = [],
                               issue: DeviceReadIssue? = nil) -> DeviceSnapshot {
        DeviceSnapshot(status: status, devices: devices, frameworkLoaded: library.loaded,
                       message: message, issue: issue)
    }
}
