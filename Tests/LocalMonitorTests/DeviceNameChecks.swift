import Foundation
import DeviceCore

// Friendly device names: known identifiers map to marketing names (never translated), unknown
// ones keep the kind + raw identifier rendering.
@MainActor
func runDeviceNameChecks(_ check: (Bool, String) -> Void) {
    let expected: [(String, String)] = [
        ("iPhone12,1", "iPhone 11"), ("iPhone12,3", "iPhone 11 Pro"), ("iPhone12,5", "iPhone 11 Pro Max"),
        ("iPhone12,8", "iPhone SE (2nd generation)"), ("iPhone13,1", "iPhone 12 mini"), ("iPhone13,2", "iPhone 12"),
        ("iPhone13,3", "iPhone 12 Pro"), ("iPhone13,4", "iPhone 12 Pro Max"), ("iPhone14,4", "iPhone 13 mini"),
        ("iPhone14,5", "iPhone 13"), ("iPhone14,2", "iPhone 13 Pro"), ("iPhone14,3", "iPhone 13 Pro Max"),
        ("iPhone14,6", "iPhone SE (3rd generation)"), ("iPhone14,7", "iPhone 14"), ("iPhone14,8", "iPhone 14 Plus"),
        ("iPhone15,2", "iPhone 14 Pro"), ("iPhone15,3", "iPhone 14 Pro Max"), ("iPhone15,4", "iPhone 15"),
        ("iPhone15,5", "iPhone 15 Plus"), ("iPhone16,1", "iPhone 15 Pro"), ("iPhone16,2", "iPhone 15 Pro Max"),
        ("iPhone17,3", "iPhone 16"), ("iPhone17,4", "iPhone 16 Plus"), ("iPhone17,1", "iPhone 16 Pro"),
        ("iPhone17,2", "iPhone 16 Pro Max"), ("iPhone17,5", "iPhone 16e"),
    ]
    for (identifier, name) in expected {
        check(DeviceNames.marketingName(productType: identifier) == name, "marketing name \(identifier)")
    }
    check(DeviceNames.knownCount == expected.count, "no identifiers beyond the verified list")
    for unknown in ["iPhone99,1", "iPad13,18", "iPhone16", "iphone16,1", " iPhone16,1", ""] {
        check(DeviceNames.marketingName(productType: unknown) == nil, "unknown identifier '\(unknown)' has no name")
    }

    let known = ConnectedDeviceSnapshot(id: "0", productType: "iPhone16,1", kind: .iPhone, batteryPercentage: 80)
    let unknown = ConnectedDeviceSnapshot(id: "1", productType: "iPad13,18", kind: .iPad, batteryPercentage: 50)
    let empty = ConnectedDeviceSnapshot(id: "2", productType: "", kind: .iPhone)
    let missing = ConnectedDeviceSnapshot(id: "3", kind: .iPad)
    for language in AppLanguage.allCases {
        L10n.language = language
        let tag = language.rawValue
        check(VisibleMetrics.deviceCardTitle(known) == DeviceCardTitle(title: "iPhone 15 Pro", detail: "iPhone16,1"),
              "known device shows its name and identifier (\(tag))")
        check(VisibleMetrics.deviceCardTitle(unknown) == DeviceCardTitle(title: L10n.deviceKind(.iPad), detail: "iPad13,18"),
              "unknown device keeps kind and identifier (\(tag))")
        check(VisibleMetrics.deviceCardTitle(empty) == DeviceCardTitle(title: L10n.deviceKind(.iPhone), detail: nil),
              "empty identifier is hidden (\(tag))")
        check(VisibleMetrics.deviceCardTitle(missing) == DeviceCardTitle(title: L10n.deviceKind(.iPad), detail: nil),
              "missing identifier is hidden (\(tag))")
    }

    // The preview fixture shows one named iPhone with details and one basic iPad.
    let fixture = PreviewFixtures.devices
    check(fixture.status == .available && fixture.devices.count == 2, "fixture has two devices")
    check(VisibleMetrics.deviceStatus(fixture) == nil, "fixture shows device cards")
    if fixture.devices.count == 2 {
        check(VisibleMetrics.deviceCardTitle(fixture.devices[0]).title == "iPhone 15 Pro", "fixture iPhone is named")
        check(VisibleMetrics.deviceRows(fixture.devices[0]).count == 8, "fixture iPhone has every row")
        check(fixture.devices[1].kind == .iPad && VisibleMetrics.deviceRows(fixture.devices[1]).count <= 1,
              "fixture iPad has only basic values")
    }
}
