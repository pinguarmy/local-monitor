# Local Monitor

A lightweight macOS menu bar app for system resources, Mac battery health, and battery information from USB-connected devices. The menu bar item can show battery charge, CPU usage or memory usage.

[Download](https://github.com/pinguarmy/local-monitor/releases) · [MIT License](LICENSE)

## Features

| Tab | Metrics |
| --- | --- |
| System | CPU usage, cores and load; GPU model and utilization; memory, swap and pressure; disk usage; network rates and totals. |
| Battery | Charge and power status, time remaining or time until full, power adapter wattage, design and full-charge capacity, estimated capacity ratio, cycles, temperature, voltage, current and battery-side power. |
| Devices | USB-connected iPhone/iPad model (with the product name for known iPhones), OS version and available battery charge, charging status, temperature, cycles and capacity. |

Unavailable metrics are hidden. Each tab updates only while you are looking at it: system metrics every 2 seconds, the Mac battery every 5 seconds (and on power events), connected devices every 10 seconds, so plugging in a phone shows up without a refresh. Intervals lengthen in Low Power Mode, and everything in the panel stops when it closes.

The menu bar item shows battery charge by default, or CPU usage on a Mac without a battery. You can switch it to CPU usage, memory usage or icon only in the panel's menu. CPU and memory modes take one light reading every 3 seconds in the background; battery and icon-only modes sample nothing while the panel is closed.

The interface is available in English and Simplified Chinese and follows the system language. Shortcuts in the panel: ⌘1–⌘3 switch tabs, ⌘R refreshes, ⌘Q quits. Launch at Login is an opt-in toggle in the panel's menu.

## Install

1. Download the package from [Releases](https://github.com/pinguarmy/local-monitor/releases). Packages named `-macos-universal.zip` run natively on Apple Silicon and Intel Macs.
2. Extract it and drag `LocalMonitor.app` into Applications or `~/Applications`.
3. Open the app and use its menu bar item.

Quit the previous version before replacing it. To connect a phone, use a data cable, unlock the device, and confirm trust yourself if macOS asks. Devices that are only visible over Wi-Fi are skipped.

The minimum deployment target is macOS 13. The Intel build is compiled and tested in CI under Rosetta 2 but has not been run on Intel hardware. This is a Beta release with an ad-hoc signature, not Apple notarization. Use the normal macOS open process if prompted; do not disable system security protections.

## Local and read-only

No network requests, uploads, history database or root access. The only things stored are your menu bar choice and, if you turn it on, the Launch at Login registration. The app does not control charging, fans or system sleep. Mobile-device support uses non-public system interfaces and is experimental; availability varies by OS and device.

The capacity ratio is not an official battery health rating. Battery-side power is not whole-system power consumption. See [metric definitions](docs/DATA_SOURCES.md), [privacy](PRIVACY.md) and [security](SECURITY.md).

## Build

Requires macOS, Swift 5.9+ and Xcode Command Line Tools. No third-party package dependencies.

```bash
bash scripts/build-app.sh      # dist/LocalMonitor.app for this Mac's architecture
bash scripts/build-app.sh --universal   # arm64 + x86_64 app and .build/universal/local-monitor-cli
bash scripts/test-direct.sh    # Standalone tests
bash scripts/install-app.sh    # Quit the app before installing
```

A full Xcode environment also supports `swift build` and `swift test`. `LOCAL_MONITOR_ARCH=x86_64 bash scripts/test-direct.sh` builds and runs the tests as x86_64 (through Rosetta 2 on Apple Silicon). The app icon is drawn at build time by `scripts/make-app-icon.swift`; the repository contains no image files.

## Command line

```bash
.build/direct/local-monitor-cli --system
.build/direct/local-monitor-cli --battery
.build/direct/local-monitor-cli --devices
.build/direct/local-monitor-cli --all
```

Each invocation outputs one JSON snapshot, without continuous background sampling. Missing fields are omitted, timestamps use ISO 8601, and explanatory text in the output is English regardless of the system language.
