# Privacy

Local Monitor reads system counters and battery information locally. It does not make network requests, upload data or save a history. Readings are taken while you look at a tab; if you set the menu bar item to CPU or memory usage, one CPU and memory reading is also taken every few seconds in the background. Nothing read is written to disk.

## Data access

- Mac power, battery, power adapter wattage, CPU, GPU, memory, disk capacity and network counters.
- Connected mobile-device model codes, OS versions and battery status.

The app does not scan user directories or read network traffic contents, destination addresses, photos, messages, user-assigned device names, serial numbers, UDIDs or pairing records. Diagnostic replies are processed in memory; only allowlisted numeric fields are retained, and other properties are neither output nor saved.

The app stores one preference, the menu bar choice, in its own macOS preferences. Launch at Login is off by default. Turning it on registers the app itself with macOS as a login item; it stores no data of its own and can be turned off in the app or in System Settings.

The CLI writes snapshots to the terminal. Preview commands render the app's own view to a specified file. Check model, timestamp and status information before sharing these outputs.

Report privacy issues through the repository's private vulnerability reporting feature. Do not publish raw device trees or pairing records.
