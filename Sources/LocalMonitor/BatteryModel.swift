import Foundation
import Combine
import BatteryCore

/// Mac battery state. AppDelegate refreshes it on power events, wake, panel open and manual
/// refresh; MonitorModel also refreshes it on a timer while the Battery tab is visible
/// (`SamplingPolicy.batteryInterval`). Reads are synchronous on the main actor.
@MainActor
final class BatteryModel: ObservableObject {
    @Published private(set) var snapshot: BatterySnapshot
    private let read: () -> BatterySnapshot
    private(set) var readCount = 1

    init(read: @escaping () -> BatterySnapshot = { BatteryReader().read() }) {
        self.read = read
        self.snapshot = read()
    }

    func refresh() { snapshot = read(); readCount += 1 }

    var status: String { BatteryPresentation.status(snapshot) }
    /// Kept for the smoke-test marker; "—" when no percentage was read.
    var percentage: String { BatteryPresentation.percentage(snapshot) ?? "—" }
}
