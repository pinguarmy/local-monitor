# Local Monitor v0.4.0 Beta

A native macOS menu bar app for system and battery monitoring.

## New in 0.4.0

- The menu bar item can show battery charge, CPU usage, memory usage or just an icon. Macs without an internal battery default to CPU usage instead of an empty battery.
- English and Simplified Chinese interface that follows the system language. Explanatory text in CLI output is English.
- Battery: time remaining on battery, time until full while charging and power adapter wattage; readings refresh every 5 seconds while the Battery tab is visible.
- System: disk usage with a usage bar; CPU usage and network rates appear about one second after the panel opens.
- Devices: the list refreshes by itself every 10 seconds while the Devices tab is visible, so plugging in or unplugging shows up without a click; a read finishes as soon as the connected devices are known instead of always waiting 1.5 seconds; known iPhones show their product name; devices visible only over Wi-Fi are skipped.
- Panel: ⌘1–⌘3 switch tabs, an opt-in Launch at Login toggle, and metric rows read as single VoiceOver elements.
- Downloads are universal (Apple Silicon and Intel) and the app has its own icon. The archive name ends in `-macos-universal.zip`.
- CLI: `-h` is accepted; device snapshots carry a machine-readable `issue` code when a read is unavailable.

## Behaviour changes from 0.3.x

- The Battery and Devices tabs now refresh on a timer while they are visible. Earlier versions refreshed them only on power events, on opening the tab and on manual refresh.
- With CPU or memory selected for the menu bar, one light reading is taken every 3 seconds while the panel is closed. Battery and icon-only modes still sample nothing in the background.
- The app stores one preference (the menu bar choice).

## Unchanged

- Unavailable metrics stay hidden. Everything in the panel stops when it closes.
- Local, read-only operation without telemetry, a history database or a background daemon.

Extract the download and place `LocalMonitor.app` in Applications. The app is ad-hoc signed and not Apple-notarized. The Intel build is tested in CI under Rosetta 2 but has not been run on Intel hardware. Mobile-device support is experimental.
