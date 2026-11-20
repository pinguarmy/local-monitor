import SwiftUI
import BatteryCore

/// Battery tab. A Mac without a battery gets a single empty state; a failed read gets a short
/// retry hint. Rows come from `VisibleMetrics` so tests can assert them.
@MainActor
struct BatterySection: View {
    @ObservedObject var model: BatteryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch model.snapshot.availability {
            case .absent:
                emptyState(title: L10n.batteryAbsentTitle, message: L10n.batteryAbsentMessage)
            case .unknown:
                emptyState(title: L10n.batteryUnknownTitle, message: L10n.batteryUnknownMessage)
            case .present:
                presentContent(model.snapshot)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func emptyState(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            NoteText(text: message, size: 12)
        }
    }

    @ViewBuilder
    private func presentContent(_ snapshot: BatterySnapshot) -> some View {
        let chargeRows = VisibleMetrics.batteryChargeRows(snapshot)
        let healthRows = VisibleMetrics.batteryHealthRows(snapshot)
        let electricalRows = VisibleMetrics.batteryElectricalRows(snapshot)
        let footnotes = VisibleMetrics.batteryFootnotes(snapshot)

        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(MonitorPage.battery.label).font(.headline).accessibilityAddTraits(.isHeader)
                Text(model.status).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if let percentage = BatteryPresentation.percentage(snapshot) {
                Text(percentage)
                    .font(.system(size: 32, weight: .medium, design: .rounded))
                    .monospacedDigit()
            }
        }
        if let percentage = snapshot.percentage {
            LevelBar(percentage: percentage, spokenLabel: L10n.batteryLevelAccessibility)
        }
        if !chargeRows.isEmpty {
            Divider()
            MetricGroup(rows: chargeRows)
        }
        if !healthRows.isEmpty {
            Divider()
            MetricGroup(rows: healthRows)
        }
        if !electricalRows.isEmpty {
            Divider()
            MetricGroup(rows: electricalRows)
        }
        if !snapshot.readErrors.isEmpty {
            NoteText(text: L10n.batteryPartialReadWarning, tone: .warning)
        }
        ForEach(Array(footnotes.enumerated()), id: \.offset) { _, note in
            NoteText(text: note, size: 10)
        }
        Divider()
        Text(L10n.updated(at: snapshot.timestamp))
            .monospacedDigit()
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
    }
}
