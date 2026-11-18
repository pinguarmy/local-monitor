import SwiftUI

/// Emphasis for a metric value. Rules stay free of SwiftUI; views map tone to color.
enum MetricTone {
    case normal, warning, critical

    var color: Color? {
        switch self {
        case .normal: return nil
        case .warning: return .orange
        case .critical: return .red
        }
    }
}

/// One visible metric: a title and an already formatted value.
struct MetricItem: Equatable {
    let title: String
    let value: String
    var tone: MetricTone = .normal
}

/// A usage bar drawn under the first row of a group (CPU usage, memory, disk).
struct MetricGauge: Equatable {
    /// 0...1.
    let fraction: Double
    let spokenLabel: String
    let spokenValue: String
}

/// Two-column metric row: secondary title on the left, monospaced value on the right.
/// VoiceOver reads it as one element (title as label, value as value).
struct MetricRow: View {
    let item: MetricItem

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(item.title).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(item.value)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .foregroundStyle(item.tone.color ?? Color.primary)
        }
        .font(.system(size: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title)
        .accessibilityValue(item.value)
    }
}

/// Small group title.
struct MetricGroupHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A titled list of rows with an optional usage bar after the first row.
struct MetricGroup: View {
    var title: String? = nil
    let rows: [MetricItem]
    var gauge: MetricGauge? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title { MetricGroupHeader(title: title) }
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                MetricRow(item: row)
                if index == 0, let gauge {
                    GaugeBar(gauge: gauge)
                }
            }
        }
    }
}

struct GaugeBar: View {
    let gauge: MetricGauge

    var body: some View {
        ProgressView(value: gauge.fraction.isFinite ? min(max(gauge.fraction, 0), 1) : 0)
            .tint(.accentColor)
            .accessibilityLabel(gauge.spokenLabel)
            .accessibilityValue(gauge.spokenValue)
    }
}

/// Battery-style level bar (Mac battery and connected devices): orange at 20% or below.
struct LevelBar: View {
    let percentage: Int
    let spokenLabel: String

    var body: some View {
        ProgressView(value: Double(min(max(percentage, 0), 100)), total: 100)
            .tint(percentage <= 20 ? .orange : .green)
            .accessibilityLabel(spokenLabel)
            .accessibilityValue(MonitorFormat.integerPercent(percentage))
    }
}

/// Wrapping secondary explanation text.
struct NoteText: View {
    let text: String
    var size: CGFloat = 11
    var tone: MetricTone = .normal

    var body: some View {
        Text(text)
            .font(.system(size: size))
            .foregroundStyle(tone.color ?? Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A tab's header row: title on the left, an optional small status caption on the right.
struct SectionHeader: View {
    let title: String
    var caption: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            Spacer()
            if let caption {
                Text(caption).monospacedDigit().font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }
}
