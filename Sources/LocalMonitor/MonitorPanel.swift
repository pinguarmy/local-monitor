import SwiftUI
import DeviceCore

/// 面板布局纯规则：尺寸常量与滚动身份逻辑集中在这里，供视图与测试共用。
///
/// 根因说明：此前 ScrollView 只有 frame(maxHeight: 510)，没有 min/ideal。
/// 设备页内容是异步的（从空到读回设备），AppKit fitting 在内容为空时可把
/// 滚动视口压到约 100pt，面板整体看起来“很扁”。这里给出稳定的最小/理想高度，
/// 屏幕较小时由父级 NSPopover 的 contentSize 再做适配。
enum PanelLayout {
    /// 面板固定宽度（点）。
    static let panelWidth: CGFloat = 420
    /// 滚动视口最小高度：内容为空或很少时面板也不会被压扁。
    static let viewportMinHeight: CGFloat = 480
    /// 滚动视口理想高度。
    static let viewportIdealHeight: CGFloat = 510
    /// 滚动视口最大高度：内容超出时滚动。
    static let viewportMaxHeight: CGFloat = 510
    /// 视口之外的固定高度开销：标题行、页签、分隔线、底栏与面板内边距。
    /// 取值使 viewportIdeal(510) + chrome(140) = 650，与父级 NSPopover contentSize 420x650 一致。
    static let chromeHeight: CGFloat = 140
    /// 根视图高度（620–650）。屏幕较小时由父级 NSPopover contentSize 再向下适配。
    static var panelMinHeight: CGFloat { viewportMinHeight + chromeHeight }
    static var panelIdealHeight: CGFloat { viewportIdealHeight + chromeHeight }
    static var panelMaxHeight: CGFloat { viewportIdealHeight + chromeHeight }
    /// 设备页首屏至少要露出设备名称与电量的高度预算（页头 + 卡片头部行）。
    static let deviceFirstScreenBudget: CGFloat = 180

    /// 给定视口高度能否在首屏露出设备名称与电量。
    static func viewportFitsDeviceFirstScreen(_ viewportHeight: CGFloat) -> Bool {
        viewportHeight >= deviceFirstScreenBudget
    }

    /// 滚动身份：仅页签或设备快照的状态/数量变化时变化，驱动滚动回顶。
    /// 系统页每 2 秒的采样快照与电池事件快照都不参与，滚动位置不会被打断。
    struct ScrollIdentity: Hashable {
        var page: MonitorPage
        var deviceStatus: String
        var deviceCount: Int
    }

    /// 只在设备页才把快照状态/数量计入身份；其他页忽略设备数据。
    static func scrollIdentity(page: MonitorPage, devices: DeviceSnapshot?) -> ScrollIdentity {
        ScrollIdentity(
            page: page,
            deviceStatus: page == .devices ? (devices?.status.rawValue ?? "none") : "ignored",
            deviceCount: page == .devices ? (devices?.devices.count ?? 0) : 0
        )
    }
}

@MainActor
struct MonitorPanel: View {
    @ObservedObject var battery: BatteryModel
    @ObservedObject var monitor: MonitorModel
    let quit: () -> Void

    /// 内容顶部锚点，配合 ScrollViewReader 回顶。
    private let scrollTopID = "monitor-panel-scroll-top"

    /// 当前滚动身份：切页签或设备快照状态/数量变化时滚动回顶。
    private var scrollIdentity: PanelLayout.ScrollIdentity {
        PanelLayout.scrollIdentity(page: monitor.page, devices: monitor.devices)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("本机监控").font(.system(size: 17, weight: .semibold))
                Spacer()
                Text("本地 · 只读").font(.caption).foregroundStyle(.secondary)
            }
            Picker("监控页面", selection: $monitor.page) {
                ForEach(MonitorPage.allCases, id: \.self) { page in Text(page.label).tag(page) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: monitor.page) { page in
                monitor.pageChanged()
                if page == .battery { battery.refresh() }
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        switch monitor.page {
                        case .system: SystemSection(snapshot: monitor.system, isSampling: monitor.isSampling)
                        case .battery: BatteryDetails(model: battery, quit: quit)
                        case .devices: DevicesSection(snapshot: monitor.devices, isReading: monitor.isReadingDevices, refresh: monitor.refreshDevices)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 2)
                    .id(scrollTopID)
                }
                .frame(minHeight: PanelLayout.viewportMinHeight,
                       idealHeight: PanelLayout.viewportIdealHeight,
                       maxHeight: PanelLayout.viewportMaxHeight)
                // 身份变化即重建滚动视图，天然回到顶部；不再跨页签保留滚动 offset。
                .id(scrollIdentity)
                .onChange(of: scrollIdentity) { _ in
                    proxy.scrollTo(scrollTopID, anchor: .top)
                }
            }
            Divider()
            HStack {
                Text(samplingLabel).font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("刷新") {
                    switch monitor.page {
                    case .system: monitor.refreshSystem()
                    case .battery: battery.refresh()
                    case .devices: monitor.refreshDevices()
                    }
                }.keyboardShortcut("r", modifiers: .command)
                .disabled(monitor.page == .devices && monitor.isReadingDevices)
                Button("退出", action: quit).keyboardShortcut("q", modifiers: .command)
            }.font(.system(size: 11))
        }
        .padding(18)
        .frame(width: PanelLayout.panelWidth)
        .frame(minHeight: PanelLayout.panelMinHeight,
               idealHeight: PanelLayout.panelIdealHeight,
               maxHeight: PanelLayout.panelMaxHeight)
    }

    private var samplingLabel: String {
        switch monitor.page {
        case .system:
            return monitor.isSampling ? (ProcessInfo.processInfo.isLowPowerModeEnabled ? "查看时每5秒 · 关闭即停" : "查看时每2秒 · 关闭即停") : "实时采样已暂停"
        case .battery: return "电池无定时轮询"
        case .devices: return "设备仅打开时与手动读取"
        }
    }
}
