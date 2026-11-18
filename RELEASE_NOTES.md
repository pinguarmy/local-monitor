# Local Monitor v0.4.0 Beta

A native macOS menu bar app for system and battery monitoring.

## New in 0.4.0

- English and Simplified Chinese interface that follows the system language. Explanatory text in CLI output is English.
- Battery: time remaining on battery, time until full while charging, and power adapter wattage.
- Macs without an internal battery get a neutral menu bar icon and a clear empty Battery tab.
- System: disk usage with a usage bar; CPU usage and network rates appear about one second after the panel opens instead of after a full sampling interval.
- Devices: a refresh finishes as soon as the connected devices are known instead of always waiting 1.5 seconds; devices visible only over Wi-Fi are skipped, as documented; a loading indicator replaces the "not read yet" text during the first read.
- Panel: ⌘1–⌘3 switch tabs, an opt-in Launch at Login toggle, and metric rows read as single VoiceOver elements.
- CLI: `-h` is accepted; device snapshots carry a machine-readable `issue` code when a read is unavailable.

## Unchanged

- Unavailable metrics stay hidden; live system sampling stops when you leave the System tab.
- Local, read-only operation without telemetry, a history database or a background daemon.

The download supports Apple Silicon. Extract it and place `LocalMonitor.app` in Applications. The app is ad-hoc signed and not Apple-notarized. Mobile-device support is experimental.
