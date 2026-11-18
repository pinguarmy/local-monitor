import SwiftUI

/// Popover content: title, tab picker, the scrolling tab content and the footer.
@MainActor
struct MonitorPanel: View {
    @ObservedObject var battery: BatteryModel
    @ObservedObject var monitor: MonitorModel
    @ObservedObject var launchAtLogin: LaunchAtLogin
    let quit: () -> Void

    /// Top anchor of the content, used with ScrollViewReader to scroll back to the top.
    private let scrollTopID = "monitor-panel-scroll-top"

    /// Current scroll identity: switching tabs or a device status/count change scrolls to the top.
    private var scrollIdentity: PanelLayout.ScrollIdentity {
        PanelLayout.scrollIdentity(page: monitor.page, devices: monitor.devices)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.appName).font(.system(size: 17, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text(L10n.panelBadge).font(.caption).foregroundStyle(.secondary)
            }
            Picker(L10n.pagePickerLabel, selection: $monitor.page) {
                ForEach(MonitorPage.allCases, id: \.self) { page in Text(page.label).tag(page) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .background(pageShortcuts)
            .onChange(of: monitor.page) { page in
                monitor.pageChanged()
                if page == .battery { battery.refresh() }
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        switch monitor.page {
                        case .system: SystemSection(snapshot: monitor.system, isSampling: monitor.isSampling)
                        case .battery: BatterySection(model: battery)
                        case .devices: DevicesSection(snapshot: monitor.devices, isReading: monitor.isReadingDevices)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 2)
                    .id(scrollTopID)
                }
                .frame(minHeight: PanelLayout.viewportMinHeight,
                       idealHeight: PanelLayout.viewportIdealHeight,
                       maxHeight: PanelLayout.viewportMaxHeight)
                // A new identity rebuilds the scroll view, which naturally starts at the top;
                // no scroll offset is kept across tabs.
                .id(scrollIdentity)
                .onChange(of: scrollIdentity) { _ in
                    proxy.scrollTo(scrollTopID, anchor: .top)
                }
            }
            Divider()
            footer
        }
        .padding(18)
        .frame(width: PanelLayout.panelWidth)
        .frame(minHeight: PanelLayout.panelMinHeight,
               idealHeight: PanelLayout.panelIdealHeight,
               maxHeight: PanelLayout.panelMaxHeight)
    }

    /// Invisible buttons behind the picker that carry the ⌘1 / ⌘2 / ⌘3 tab shortcuts.
    private var pageShortcuts: some View {
        ZStack {
            Button(MonitorPage.system.label) { monitor.page = .system }
                .keyboardShortcut("1", modifiers: .command)
            Button(MonitorPage.battery.label) { monitor.page = .battery }
                .keyboardShortcut("2", modifiers: .command)
            Button(MonitorPage.devices.label) { monitor.page = .devices }
                .keyboardShortcut("3", modifiers: .command)
        }
        .opacity(0)
        .accessibilityHidden(true)
    }

    private var footer: some View {
        HStack {
            Text(samplingCaption)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            Button(L10n.refresh) {
                switch monitor.page {
                case .system: monitor.refreshSystem()
                case .battery: battery.refresh()
                case .devices: monitor.refreshDevices()
                }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(monitor.page == .devices && monitor.isReadingDevices)
            Button(L10n.quit, action: quit).keyboardShortcut("q", modifiers: .command)
            moreMenu
        }
        .font(.system(size: 11))
    }

    private var moreMenu: some View {
        Menu {
            if launchAtLogin.isSupported {
                Toggle(L10n.launchAtLogin, isOn: $launchAtLogin.wantsEnabled)
            }
            if let version = AppInfo.version {
                Button(L10n.version(version)) {}
                    .disabled(true)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(L10n.moreMenu)
        .help(L10n.moreMenu)
    }

    /// Footer caption explaining the current tab's sampling policy.
    private var samplingCaption: String {
        switch monitor.page {
        case .system:
            guard monitor.isSampling else { return L10n.systemSamplingPaused }
            let interval = SamplingPolicy.systemInterval(panelVisible: true, page: .system, isSleeping: false,
                                                         lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled) ?? 2
            return L10n.systemSamplingEvery(seconds: Int(interval))
        case .battery: return L10n.batteryPolicyCaption
        case .devices: return L10n.devicesPolicyCaption
        }
    }
}
