#!/bin/bash
# No SwiftPM manifest subprocess or sandbox settings are changed.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
# Host architecture into .build/direct by default; LOCAL_MONITOR_ARCH=arm64|x86_64 builds that
# architecture into .build/direct-<arch> instead (see direct-arch.sh).
source "$ROOT/scripts/direct-arch.sh"
mkdir -p "$OUT/module-cache"
SWIFTC="$(xcrun --find swiftc)"
SDK="$(xcrun --show-sdk-path)"
COMMON=(-swift-version 5 -O -sdk "$SDK" -target "$ARCH-apple-macosx13.0" -module-cache-path "$OUT/module-cache"
  -file-prefix-map "$ROOT=/src/LocalMonitor" -debug-prefix-map "$ROOT=/src/LocalMonitor")
shopt -s nullglob
# BatteryCore: static library + module (IOKit). -enable-testing allows @testable import from tests.
"$SWIFTC" "${COMMON[@]}" -parse-as-library -enable-testing -emit-library -static -emit-module -module-name BatteryCore \
  "$ROOT"/Sources/BatteryCore/*.swift \
  -emit-module-path "$OUT/BatteryCore.swiftmodule" -o "$OUT/libBatteryCore.a"
# SystemCore: static library + module (IOKit, Metal).
"$SWIFTC" "${COMMON[@]}" -parse-as-library -enable-testing -emit-library -static -emit-module -module-name SystemCore \
  -framework IOKit -framework Metal \
  "$ROOT"/Sources/SystemCore/*.swift \
  -emit-module-path "$OUT/SystemCore.swiftmodule" -o "$OUT/libSystemCore.a"
# DeviceCore: static library + module (dlopen-based native backend, no extra frameworks).
"$SWIFTC" "${COMMON[@]}" -parse-as-library -enable-testing -emit-library -static -emit-module -module-name DeviceCore \
  "$ROOT"/Sources/DeviceCore/*.swift \
  -emit-module-path "$OUT/DeviceCore.swiftmodule" -o "$OUT/libDeviceCore.a"
# CLI: main.swift uses `@main ... static func main() async`, so -parse-as-library is required.
"$SWIFTC" "${COMMON[@]}" -parse-as-library -I "$OUT" -L "$OUT" \
  -lBatteryCore -lSystemCore -lDeviceCore -framework IOKit -framework Metal \
  "$ROOT/Sources/MonitorCLI/main.swift" -o "$OUT/local-monitor-cli"
# UI: glob all Sources/LocalMonitor/*.swift so newly added files are never missed.
ui_sources=("$ROOT"/Sources/LocalMonitor/*.swift)
if ((${#ui_sources[@]} == 0)); then
  printf 'No UI sources found under Sources/LocalMonitor\n' >&2
  exit 1
fi
"$SWIFTC" "${COMMON[@]}" -parse-as-library -I "$OUT" -L "$OUT" \
  -lBatteryCore -lSystemCore -lDeviceCore \
  -framework IOKit -framework Metal -framework AppKit -framework SwiftUI \
  "${ui_sources[@]}" -o "$OUT/LocalMonitor"
printf 'Direct native build complete (%s): %s\n' "$ARCH" "$OUT"
