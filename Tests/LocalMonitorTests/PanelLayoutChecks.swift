import Foundation
import DeviceCore

// 面板布局的纯规则检查。由 PresentationRunner 调用并汇入其断言计数，本文件不含 @main。
// 只验证 PanelLayout 的常量关系与滚动身份逻辑；原生实际渲染 preview 由父级统一做一次。

/// 面板布局检查：最小视口、预期总高度、设备首屏预算、切页签/快照身份。
func runPanelLayoutChecks(_ check: (Bool, String) -> Void) {
    // 最小视口高度：异步内容为空时面板不被压扁（截图反馈的根因）。
    check(PanelLayout.viewportMinHeight >= 480, "viewport has a minimum height (>=480)")
    check(PanelLayout.viewportMinHeight <= PanelLayout.viewportIdealHeight, "viewport min <= ideal")
    check(PanelLayout.viewportIdealHeight <= PanelLayout.viewportMaxHeight, "viewport ideal <= max")
    check(PanelLayout.viewportMaxHeight <= 510, "viewport max stays within brief limit")

    // 预期总高度：root = viewport + chrome，落在 620–665，与 popover contentSize 420x650 一致。
    check(PanelLayout.panelWidth == 420, "panel width stays 420")
    check(PanelLayout.panelMinHeight == PanelLayout.viewportMinHeight + PanelLayout.chromeHeight,
          "panel min = viewport min + chrome")
    check(PanelLayout.panelIdealHeight == PanelLayout.viewportIdealHeight + PanelLayout.chromeHeight,
          "panel ideal = viewport ideal + chrome")
    check(PanelLayout.panelIdealHeight == 650, "panel ideal height matches popover contentSize 650")
    check(PanelLayout.panelMinHeight >= 620 && PanelLayout.panelMaxHeight <= 665,
          "panel height stays within 620-665")

    // 设备名称与电量在首屏：最小视口必须容纳设备卡片头部预算。
    check(PanelLayout.viewportFitsDeviceFirstScreen(PanelLayout.viewportMinHeight),
          "device name/battery visible in first screen at min viewport")
    check(!PanelLayout.viewportFitsDeviceFirstScreen(PanelLayout.deviceFirstScreenBudget - 1),
          "first-screen budget rule rejects smaller viewport")

    // 滚动身份：切页签必变化（回顶），同页同数据不变化（不打扰滚动）。
    let noDevice = DeviceSnapshot(status: .noDevice, message: "")
    let oneDevice = DeviceSnapshot(
        status: .available,
        devices: [ConnectedDeviceSnapshot(id: "0", kind: .iPhone, batteryPercentage: 80)],
        message: ""
    )
    let twoDevices = DeviceSnapshot(
        status: .available,
        devices: [ConnectedDeviceSnapshot(id: "0", kind: .iPhone, batteryPercentage: 80),
                  ConnectedDeviceSnapshot(id: "1", kind: .iPad, batteryPercentage: 55)],
        message: ""
    )
    let locked = DeviceSnapshot(status: .requiresUnlockAndTrust, message: "")

    check(PanelLayout.scrollIdentity(page: .system, devices: nil)
            != PanelLayout.scrollIdentity(page: .devices, devices: nil),
          "tab switch changes identity")
    check(PanelLayout.scrollIdentity(page: .battery, devices: nil)
            != PanelLayout.scrollIdentity(page: .devices, devices: nil),
          "battery to devices changes identity")
    check(PanelLayout.scrollIdentity(page: .devices, devices: noDevice)
            != PanelLayout.scrollIdentity(page: .devices, devices: oneDevice),
          "device status change changes identity")
    check(PanelLayout.scrollIdentity(page: .devices, devices: oneDevice)
            != PanelLayout.scrollIdentity(page: .devices, devices: twoDevices),
          "device count change changes identity")
    check(PanelLayout.scrollIdentity(page: .devices, devices: noDevice)
            != PanelLayout.scrollIdentity(page: .devices, devices: locked),
          "noDevice to requiresUnlock changes identity")
    check(PanelLayout.scrollIdentity(page: .devices, devices: oneDevice)
            == PanelLayout.scrollIdentity(page: .devices, devices: oneDevice),
          "same status and count keep identity (manual refresh does not jump)")

    // 非设备页忽略设备数据：系统页 2 秒采样与电池事件都不会重置滚动。
    check(PanelLayout.scrollIdentity(page: .system, devices: nil)
            == PanelLayout.scrollIdentity(page: .system, devices: twoDevices),
          "system page identity ignores device data")
    check(PanelLayout.scrollIdentity(page: .battery, devices: nil)
            == PanelLayout.scrollIdentity(page: .battery, devices: twoDevices),
          "battery page identity ignores device data")
}
