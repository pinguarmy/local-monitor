import SwiftUI
import DeviceCore

/// Devices tab. All status text is derived from `status` + `issue` via `VisibleMetrics`;
/// `DeviceSnapshot.message` is CLI diagnostics and is never displayed.
@MainActor
struct DevicesSection: View {
    let snapshot: DeviceSnapshot?
    let isReading: Bool

    /// "Reading…" in the header only while a shown refresh of an existing snapshot runs (manual
    /// Refresh); a first read shows the spinner in the body instead. Timer reads are silent.
    private var headerCaption: String? {
        guard let snapshot else { return nil }
        return isReading ? L10n.reading : L10n.updated(at: snapshot.capturedAt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: MonitorPage.devices.label, caption: headerCaption)
            if let snapshot {
                content(snapshot)
            } else if isReading {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(L10n.reading).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            } else {
                NoteText(text: L10n.devicesNotRead)
            }
            Divider()
            NoteText(text: VisibleMetrics.deviceNote, size: 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func content(_ snapshot: DeviceSnapshot) -> some View {
        if let display = VisibleMetrics.deviceStatus(snapshot) {
            VStack(alignment: .leading, spacing: 8) {
                MetricRow(item: MetricItem(title: L10n.status, value: display.status, tone: display.tone))
                if let detail = display.detail {
                    NoteText(text: detail)
                }
                if !display.steps.isEmpty {
                    StepList(steps: display.steps)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(snapshot.devices) { device in
                    DeviceCard(device: device)
                }
                if let note = VisibleMetrics.deviceIssueNote(snapshot) {
                    NoteText(text: note, tone: .warning)
                }
            }
        }
    }
}

/// Numbered guidance steps.
struct StepList: View {
    let steps: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(String(index + 1) + ".").monospacedDigit()
                    Text(step).fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// One connected device: name (or kind), model identifier and charge in the header, then only the values read.
struct DeviceCard: View {
    let device: ConnectedDeviceSnapshot

    private var rows: [MetricItem] { VisibleMetrics.deviceRows(device) }
    private var header: DeviceCardTitle { VisibleMetrics.deviceCardTitle(device) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(header.title)
                    .font(.system(size: 12, weight: .semibold))
                if let detail = header.detail {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let percentage = device.batteryPercentage {
                    Text(MonitorFormat.integerPercent(percentage))
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .monospacedDigit()
                }
            }
            if let percentage = device.batteryPercentage {
                LevelBar(percentage: percentage, spokenLabel: L10n.deviceBatteryAccessibility)
            }
            if !rows.isEmpty {
                MetricGroup(rows: rows)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}
