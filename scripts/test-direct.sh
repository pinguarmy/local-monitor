#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
OUT="$ROOT/.build/direct"
shopt -s nullglob
# Always rebuild: a pre-existing archive can be older than the sources being tested.
bash "$ROOT/scripts/build-direct.sh"
ARCH="$(uname -m)"
COMMON=(-swift-version 5 -sdk "$(xcrun --show-sdk-path)" -target "$ARCH-apple-macosx13.0" -module-cache-path "$OUT/module-cache" -parse-as-library -I "$OUT" -L "$OUT" -lBatteryCore -lSystemCore -lDeviceCore -framework IOKit -framework Metal)
python3 - "$ROOT" <<'PY'
import pathlib, re, sys
root = pathlib.Path(sys.argv[1])
tests = (root / 'Tests/BatteryCoreTests/BatteryDecoderTests.swift').read_text()
runner = (root / 'Tests/BatteryCoreTests/StandaloneRunner.swift').read_text()
defined = set(re.findall(r'func (test\w+)\(', tests))
registered = set(re.findall(r'tests\.(test\w+)', runner))
if defined != registered:
    raise SystemExit(f'Standalone test registration mismatch: missing={defined-registered}, unknown={registered-defined}')
print(f'Standalone registration: {len(defined)} tests, all registered')
PY
xcrun swiftc "${COMMON[@]}" -D BATTERY_STANDALONE \
  "$ROOT/Tests/BatteryCoreTests/BatteryDecoderTests.swift" \
  "$ROOT/Tests/BatteryCoreTests/StandaloneRunner.swift" -o "$OUT/battery-core-tests"
"$OUT/battery-core-tests"
# Standalone module tests: compile every Tests/<dir>/*.swift as one binary with its own @main.
# A missing or empty test directory is a hard failure, never a silent skip.
# Each module passes its explicit -D flag (documented at the top of its StandaloneRunner.swift);
# the module libraries are built with -enable-testing so @testable import works.
run_standalone_tests() {
  local dir="$1" bin="$2"
  shift 2
  local files=("$ROOT"/Tests/"$dir"/*.swift)
  if ((${#files[@]} == 0)); then
    printf 'Missing standalone tests: Tests/%s/*.swift\n' "$dir" >&2
    exit 1
  fi
  xcrun swiftc "${COMMON[@]}" "$@" "${files[@]}" -o "$OUT/$bin"
  "$OUT/$bin"
}
run_standalone_tests SystemCoreTests system-core-tests -D SYSTEM_STANDALONE
run_standalone_tests DeviceCoreTests device-core-tests -D DEVICE_STANDALONE
# UI tests: link all three modules and compile every UI source plus every UI test file.
ui_sources=("$ROOT"/Sources/LocalMonitor/*.swift)
ui_tests=("$ROOT"/Tests/LocalMonitorTests/*.swift)
if ((${#ui_sources[@]} == 0)); then
  printf 'No UI sources found under Sources/LocalMonitor\n' >&2
  exit 1
fi
if ((${#ui_tests[@]} == 0)); then
  printf 'Missing UI tests: Tests/LocalMonitorTests/*.swift\n' >&2
  exit 1
fi
xcrun swiftc "${COMMON[@]}" -D BATTERY_UI_TESTS -framework AppKit -framework SwiftUI \
  "${ui_sources[@]}" "${ui_tests[@]}" -o "$OUT/battery-ui-tests"
"$OUT/battery-ui-tests"
