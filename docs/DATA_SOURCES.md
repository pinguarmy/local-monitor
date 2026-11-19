# Metric definitions and sources

## Mac battery

IOPowerSources provides charge, charging and power-source status. Time remaining and time until full are the system's own estimates in minutes; a value of -1 means the system is still calculating and is omitted, time remaining is reported only while discharging on battery power, and time until full only while charging. Power adapter wattage is the single `Watts` value from the public external power adapter details; no other adapter property is read. Additional values use read-only IOKit property calls. Temperature prefers the public Celsius field; the selected AppleSmartBatteryPack.BatteryData source uses hundredths of a degree Celsius, while Intel SBS data uses explicitly identified decikelvin units. Units are not guessed from numeric magnitude.

The capacity ratio is full-charge capacity divided by design capacity in the same units. It can exceed 100% and is not an official health rating. Battery-side power is voltage multiplied by current, not charger capacity or whole-system power consumption. Readings with ambiguous units are omitted.

## System

CPU usage uses Mach tick differences; load averages are not percentages. When sampling starts, one extra sample is taken about a second after the first so that the first difference is available early. The menu bar's CPU and memory modes use the same two Mach reads and nothing else: no GPU, disk or network access. GPU utilization uses known driver-provided percentage keys. Multiple accelerators that cannot be associated with one GPU are not combined.

Used memory estimates anonymous pages minus purgeable pages, plus wired and compressor pages. Available memory is total minus estimated usage, not an allocation guarantee. Pressure is read separately from the kernel. Disk figures come from root-volume statfs data; APFS volumes may share space. Used space is total capacity minus the space available to unprivileged processes, so it can differ from Finder, which also counts purgeable space as available.

Network rates use differences in 64-bit counters for active physical enN interfaces, excluding loopback, VPN, bridge and AWDL overlays. Addresses and traffic contents are not read. These totals are not an internet billing meter.

## Mobile devices

The system's non-public MobileDevice interface reuses an existing trusted session. Only wired connections are read: a device that reports a Wi-Fi interface type is skipped, which also prevents one device from appearing twice. A scan ends once the list of connected devices has been stable for a moment, or at its fixed limit when no device is found. Basic values are queried by individual key. Detailed battery readings use a fixed `IORegistry / EntryName=AppleSmartBatteryPack` request and allowlisted fields from `Diagnostics.IORegistry.BatteryData`.

Product names for known iPhone model codes come from a fixed table in the app; unknown codes are shown as reported. Temperature is divided by 100 for Celsius. VirtualTemperature is not substituted for physical temperature. Full-charge capacity prefers AppleRawMaxCapacity, then the same source's NominalChargeCapacity; DesignCapacity is design capacity in mAh. Top-level percentage values never populate mAh fields. Missing values are omitted.

## References

These references document APIs, protocols and units; they are not bundled dependencies.

- [Apple IOPowerSources](https://developer.apple.com/documentation/iokit/iopowersources)
- [Apple IOPSKeys.h power source keys](https://developer.apple.com/documentation/iokit/iopskeys_h)
- [Apple SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)
- [Stats battery reader](https://github.com/exelban/stats/blob/master/Modules/Battery/readers.swift)
- [libimobiledevice diagnostics_relay protocol](https://github.com/libimobiledevice/libimobiledevice/blob/master/src/diagnostics_relay.c)
- [pymobiledevice3 diagnostic requests](https://github.com/doronz88/pymobiledevice3/blob/master/pymobiledevice3/services/diagnostics.py)
- [pymobiledevice3 iOS temperature discussion](https://github.com/doronz88/pymobiledevice3/discussions/621)
- [ios-deploy MobileDevice declarations](https://github.com/ios-control/ios-deploy/blob/master/src/ios-deploy/MobileDevice.h)
- [mobdevim declarations](https://github.com/DerekSelander/mobdevim/blob/master/mobdevim/misc/ExternalDeclarations.h)
- [iOS raw battery capacity](https://maydur.st/2022-03-30-ios-battery/)
