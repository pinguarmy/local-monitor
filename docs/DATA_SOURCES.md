# 指标口径与公开参考

## Mac 电池

优先读取 IOPowerSources 的电量、充电、供电和可得状态，额外属性通过 IOKit 的只读属性函数读取。温度优先使用公开摄氏度字段；选定 AppleSmartBatteryPack.BatteryData 来源以百分之一摄氏度换算，Intel SBS 来源使用明确的 deciKelvin 单位，不根据数值大小猜单位。

容量比为同单位满充容量除以设计容量，可超过 100%，不是系统官方健康评级。电池侧功率为电压与电流的乘积，不是充电器额定功率或整机耗电。单位不明确的读数省略。

## 系统

CPU 使用率为 Mach tick 差分，负载不是百分比。GPU 使用率来自驱动公开的已知百分比键，多个无法对应的加速器不合并冒充单个 GPU。

内存已用估算为匿名页减可清除页，加 wired 和 compressor；可用量为总量减已用估算，不是分配保证。压力读取内核状态。磁盘是根卷 statfs 数据，APFS 卷可能共享空间。

网络速率为启用 enN 物理接口的 64 位计数差分，排除 loopback、VPN、bridge 和 AWDL 叠加计数。不读取地址和流量内容，也不等于互联网账单流量。

## 移动设备

使用系统 MobileDevice 非公有动态接口，复用用户已有的受信任会话。基础读取按单键获取型号、系统和电池状态。高级读取固定发送 `IORegistry / EntryName=AppleSmartBatteryPack`，只提取 `Diagnostics.IORegistry.BatteryData` 数值白名单。

Temperature 除以 100 换算摄氏度，VirtualTemperature 不冒充物理温度。满充容量优先 AppleRawMaxCapacity，再使用同源 NominalChargeCapacity；DesignCapacity 为设计 mAh。顶层百分比容量不进入 mAh 字段。未返回的字段直接省略。

## 参考链接

以下项目用于核对公开 API、协议和单位，不是捆绑依赖。不包含其二进制或资源，不包含闭源应用实现。

- [Apple IOPowerSources 文档](https://developer.apple.com/documentation/iokit/iopowersources)
- [Stats 电池读取参考](https://github.com/exelban/stats/blob/master/Modules/Battery/readers.swift)
- [libimobiledevice diagnostics_relay 协议](https://github.com/libimobiledevice/libimobiledevice/blob/master/src/diagnostics_relay.c)
- [pymobiledevice3 诊断请求](https://github.com/doronz88/pymobiledevice3/blob/master/pymobiledevice3/services/diagnostics.py)
- [pymobiledevice3 iOS 温度讨论](https://github.com/doronz88/pymobiledevice3/discussions/621)
- [ios-deploy MobileDevice 声明](https://github.com/ios-control/ios-deploy/blob/master/src/ios-deploy/MobileDevice.h)
- [mobdevim 外部声明](https://github.com/DerekSelander/mobdevim/blob/master/mobdevim/misc/ExternalDeclarations.h)
- [iOS 原始电池容量说明](https://maydur.st/2022-03-30-ios-battery/)
