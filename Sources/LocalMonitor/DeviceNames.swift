import Foundation

/// Marketing names for connected-device product types. Product names are not translated.
/// Only identifiers known with certainty are listed: a wrong name is worse than a code, so
/// anything missing keeps today's "iPhone  iPhone16,1" rendering.
enum DeviceNames {
    private static let names: [String: String] = [
        "iPhone12,1": "iPhone 11",
        "iPhone12,3": "iPhone 11 Pro",
        "iPhone12,5": "iPhone 11 Pro Max",
        "iPhone12,8": "iPhone SE (2nd generation)",
        "iPhone13,1": "iPhone 12 mini",
        "iPhone13,2": "iPhone 12",
        "iPhone13,3": "iPhone 12 Pro",
        "iPhone13,4": "iPhone 12 Pro Max",
        "iPhone14,4": "iPhone 13 mini",
        "iPhone14,5": "iPhone 13",
        "iPhone14,2": "iPhone 13 Pro",
        "iPhone14,3": "iPhone 13 Pro Max",
        "iPhone14,6": "iPhone SE (3rd generation)",
        "iPhone14,7": "iPhone 14",
        "iPhone14,8": "iPhone 14 Plus",
        "iPhone15,2": "iPhone 14 Pro",
        "iPhone15,3": "iPhone 14 Pro Max",
        "iPhone15,4": "iPhone 15",
        "iPhone15,5": "iPhone 15 Plus",
        "iPhone16,1": "iPhone 15 Pro",
        "iPhone16,2": "iPhone 15 Pro Max",
        "iPhone17,3": "iPhone 16",
        "iPhone17,4": "iPhone 16 Plus",
        "iPhone17,1": "iPhone 16 Pro",
        "iPhone17,2": "iPhone 16 Pro Max",
        "iPhone17,5": "iPhone 16e",
    ]

    /// Exact match only; nil for unknown or empty identifiers.
    static func marketingName(productType: String) -> String? {
        names[productType]
    }

    /// Number of known identifiers, for tests.
    static var knownCount: Int { names.count }
}
