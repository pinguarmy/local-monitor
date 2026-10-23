# Local Monitor

A lightweight macOS menu bar app for system resources, Mac battery health, and battery information from USB-connected devices.

[Download](https://github.com/pinguarmy/local-monitor/releases) · [MIT License](LICENSE)

## Features

| Tab | Metrics |
| --- | --- |
| System | CPU usage, cores and load; GPU model and utilization; memory, swap and pressure; disk capacity; network rates and totals. |
| Battery | Charge and power status, design and full-charge capacity, estimated capacity ratio, cycles, temperature, voltage, current and battery-side power. |
| Devices | Connected iPhone/iPad model, OS version and available battery charge, charging status, temperature, cycles and capacity. |

Unavailable metrics are hidden. System metrics update only while the System tab is visible and stop when the panel closes. Mac battery readings use power events or manual refresh; device readings run when you open the Devices tab or refresh it.

## Install

1. Download the Apple Silicon package from [Releases](https://github.com/pinguarmy/local-monitor/releases).
2. Extract it and drag `LocalMonitor.app` into Applications or `~/Applications`.
3. Open the app and use its menu bar item.

Quit the previous version before replacing it. To connect a phone, use a data cable, unlock the device, and confirm trust yourself if macOS asks.

The minimum deployment target is macOS 13. Downloads currently support Apple Silicon; Intel users can build from source. This is a Beta release with an ad-hoc signature, not Apple notarization. Use the normal macOS open process if prompted; do not disable system security protections.

## Local and read-only

No network requests, uploads, history database or root access. The app does not control charging, fans or system sleep. Mobile-device support uses non-public system interfaces and is experimental; availability varies by OS and device.

The capacity ratio is not an official battery health rating. Battery-side power is not whole-system power consumption. See [metric definitions](docs/DATA_SOURCES.md), [privacy](PRIVACY.md) and [security](SECURITY.md).

## Build

Requires macOS, Swift 5.9+ and Xcode Command Line Tools. No third-party package dependencies.

```bash
bash scripts/build-app.sh      # dist/LocalMonitor.app
bash scripts/test-direct.sh   # Standalone tests
bash scripts/install-app.sh   # Quit the app before installing
```

A full Xcode environment also supports `swift build` and `swift test`.

## Command line

```bash
.build/direct/local-monitor-cli --system
.build/direct/local-monitor-cli --battery
.build/direct/local-monitor-cli --devices
.build/direct/local-monitor-cli --all
```

Each invocation outputs one JSON snapshot, without continuous background sampling. Missing fields are omitted and timestamps use ISO 8601.
