import SwiftUI
import SystemCore

/// System tab. Rows come from `VisibleMetrics`; sampling lifecycle lives in `MonitorModel`.
@MainActor
struct SystemSection: View {
    let snapshot: SystemSnapshot?
    let isSampling: Bool

    private var headerCaption: String? {
        if isSampling { return L10n.sampling }
        return snapshot.map { L10n.updated(at: $0.timestamp) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: MonitorPage.system.label, caption: headerCaption)
            if let snapshot {
                systemGroups(snapshot)
            } else {
                NoteText(text: L10n.systemNotSampled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Each group appears only when it has rows; dividers go only between visible groups.
    @ViewBuilder
    private func systemGroups(_ snapshot: SystemSnapshot) -> some View {
        let cpuRows = VisibleMetrics.cpuRows(snapshot.cpu)
        let gpuRows = VisibleMetrics.gpuRows(snapshot.gpu)
        let memoryRows = VisibleMetrics.memoryRows(snapshot.memory)
        let diskRows = VisibleMetrics.diskRows(snapshot.disk)
        let networkRows = VisibleMetrics.networkRows(snapshot.network)
        let showCPU = !cpuRows.isEmpty
        let showGPU = !gpuRows.isEmpty
        let showMemory = !memoryRows.isEmpty
        let showDisk = !diskRows.isEmpty
        let showNetwork = !networkRows.isEmpty

        if showCPU {
            MetricGroup(title: L10n.groupCPU, rows: cpuRows, gauge: VisibleMetrics.cpuGauge(snapshot.cpu))
        }
        if showGPU {
            if showCPU { Divider() }
            MetricGroup(title: L10n.groupGPU, rows: gpuRows)
        }
        if showMemory {
            if showCPU || showGPU { Divider() }
            MetricGroup(title: L10n.groupMemory, rows: memoryRows, gauge: VisibleMetrics.memoryGauge(snapshot.memory))
        }
        if showDisk {
            if showCPU || showGPU || showMemory { Divider() }
            MetricGroup(title: L10n.groupDisk, rows: diskRows, gauge: VisibleMetrics.diskGauge(snapshot.disk))
        }
        if showNetwork {
            if showCPU || showGPU || showMemory || showDisk { Divider() }
            MetricGroup(title: L10n.groupNetwork, rows: networkRows)
        }
        // Machine state comes from non-optional fields and is always visible.
        if showCPU || showGPU || showMemory || showDisk || showNetwork { Divider() }
        MetricGroup(title: L10n.groupMachine, rows: VisibleMetrics.machineRows(snapshot))
    }
}
