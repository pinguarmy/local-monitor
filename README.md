# Local Monitor · 本机监控

轻量的 macOS 菜单栏监控工具，在一个面板里查看系统资源、Mac 电池和 USB 连接设备的电池信息。

[下载](https://github.com/pinguarmy/local-monitor/releases) · [发布记录](https://github.com/pinguarmy/local-monitor/releases) · [MIT 许可证](LICENSE)

## 功能

| 页面 | 内容 |
| --- | --- |
| 系统 | CPU 使用率、核心与负载，GPU 型号与利用率，内存、交换与压力，磁盘容量，网络速率与累计量。 |
| 电池 | 电量与充电状态，设计和满充容量，估算容量比，循环次数，温度、电压、电流与电池侧功率。 |
| 设备 | USB 连接的 iPhone/iPad 型号、系统版本，以及可读取的电量、充电状态、温度、循环和容量。 |

缺失的指标自动隐藏，不显示占位值。系统指标只在系统页可见时更新，关闭面板即停止；Mac 电池按电源事件或手动刷新读取，设备仅在打开页面或手动刷新时读取。

## 安装

1. 在 [Releases](https://github.com/pinguarmy/local-monitor/releases) 下载 Apple Silicon 安装包。
2. 解压，将 `LocalMonitor.app` 拖入“应用程序”或 `~/Applications`。
3. 打开应用，从菜单栏进入监控面板。

更新前请退出旧版。连接手机时使用数据线，解锁设备，并按系统提示自行确认信任。

最低系统声明为 macOS 13。当前提供 Apple Silicon 下载包，Intel 可自行构建。应用为 Beta，采用 ad-hoc 签名，尚未经过 Apple 公证；如被拦截，请使用 macOS 正常的打开流程，不要关闭系统安全保护。

## 本地、只读

不联网、不上传数据、不保存历史，不需要 root，也不控制充电、风扇或系统睡眠。移动设备功能使用非公有系统接口，属于实验性功能，支持情况随系统和设备变化。

容量比不是系统官方健康评级，电池侧功率不是整机功耗。详见 [数据口径](docs/DATA_SOURCES.md)、[隐私说明](PRIVACY.md) 和 [安全说明](SECURITY.md)。

## 构建

需要 macOS、Swift 5.9+ 和 Xcode Command Line Tools，无第三方包依赖。

```bash
bash scripts/build-app.sh      # dist/LocalMonitor.app
bash scripts/test-direct.sh   # 独立测试
bash scripts/install-app.sh   # 安装前先退出应用
```

完整 Xcode 环境也可使用 `swift build` 和 `swift test`。

## 命令行

```bash
.build/direct/local-monitor-cli --system
.build/direct/local-monitor-cli --battery
.build/direct/local-monitor-cli --devices
.build/direct/local-monitor-cli --all
```

每次运行输出一个 JSON 快照，不在后台持续采样。缺失字段省略，时间使用 ISO 8601。
