# Security

This is an early Beta release. Report security issues through GitHub's private vulnerability reporting feature. If unavailable, open an issue without sensitive details to request a private contact channel. Do not publish tokens, serial numbers, pairing records or raw diagnostic replies.

## Permissions and operations

The app does not require root, pair or trust devices automatically, install device-side software, or change charging, fans, sleep or system security settings. Device communication sends a fixed battery IORegistry read. There is no arbitrary request interface and no Restart, Shutdown, Sleep or property-write command.

There is no network service, automatic updater, third-party runtime dependency, account or embedded credential. The software is provided as-is under the MIT License.

## Known risks

MobileDevice is a non-public system interface. Its ABI and behavior may change. Native calls run off the main thread; a timeout lets the UI return, and a single-task gate prevents repeated calls from accumulating. Socket and loop deadlines provide additional limits. These measures cannot forcibly terminate a private-framework hang or isolate a native crash. Restart the app if necessary.

Device diagnostics run only when you open the Devices tab or manually refresh it. You can use the System and Mac Battery tabs without using the experimental device feature.

Replies are limited to 256 KiB and only allowlisted numeric fields at a specific nested path are extracted. Values are checked for type, range and source-specific units, but untested systems and firmware may change their meaning. Do not use these readings for medical, safety or repair decisions.

## Signing

Downloads are ad-hoc signed, without Developer ID signing or Apple notarization. Check the source and SHA-256 checksum. Do not disable Gatekeeper or SIP to run the app. Available open options depend on macOS version and policy.
