#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
# Same selection as build-direct.sh: host architecture in .build/direct by default, or
# LOCAL_MONITOR_ARCH=arm64|x86_64 in .build/direct-<arch> (x86_64 runs through Rosetta 2).
source "$ROOT/scripts/direct-arch.sh"
shopt -s nullglob
# Always rebuild: a pre-existing archive can be older than the sources being tested.
# build-direct.sh reads the same LOCAL_MONITOR_ARCH from the environment.
bash "$ROOT/scripts/build-direct.sh"
COMMON=(-swift-version 5 -sdk "$(xcrun --show-sdk-path)" -target "$ARCH-apple-macosx13.0" -module-cache-path "$OUT/module-cache" -parse-as-library -I "$OUT" -L "$OUT" -lBatteryCore -lSystemCore -lDeviceCore -framework IOKit -framework Metal)
# Run a test binary only after checking it is exactly the selected architecture, so an
# x86_64 pass cannot silently test a native build. A foreign slice runs via `arch`, which
# fails loudly (instead of falling back) when Rosetta 2 is not installed.
run_test_binary() {
  local bin="$1" actual
  actual="$(lipo -archs "$bin")"
  if [ "$actual" != "$ARCH" ]; then
    printf '%s: expected architecture %s, found %s\n' "$bin" "$ARCH" "$actual" >&2
    exit 1
  fi
  if [ "$ARCH" = "$(uname -m)" ]; then
    "$bin"
  else
    /usr/bin/arch "-$ARCH" "$bin"
  fi
}
# Every standalone runner keeps a hand-written list of cases. Fail before compiling when a
# defined test is not registered (it would silently never run) or a registered one is gone.
python3 - "$ROOT" <<'PY'
import pathlib, re, sys
root = pathlib.Path(sys.argv[1])
total = 0
for module in ('BatteryCoreTests', 'SystemCoreTests', 'DeviceCoreTests'):
    directory = root / 'Tests' / module
    runner = directory / 'StandaloneRunner.swift'
    sources = [path for path in sorted(directory.glob('*.swift')) if path != runner]
    if not runner.is_file() or not sources:
        raise SystemExit(f'{module}: missing StandaloneRunner.swift or test sources')
    defined = set()
    for path in sources:
        defined |= set(re.findall(r'\bfunc (test\w+)\(', path.read_text()))
    registered = set(re.findall(r'\.(test\w+)\b', runner.read_text()))
    if not defined:
        raise SystemExit(f'{module}: no test functions found')
    if defined != registered:
        raise SystemExit(f'{module}: standalone registration mismatch: '
                         f'unregistered={sorted(defined - registered)}, unknown={sorted(registered - defined)}')
    total += len(defined)
    print(f'Standalone registration: {module}: {len(defined)} tests, all registered')
print(f'Standalone registration: {total} tests across all modules')
PY
printf 'Standalone tests: architecture %s, output %s\n' "$ARCH" "$OUT"
xcrun swiftc "${COMMON[@]}" -D BATTERY_STANDALONE \
  "$ROOT/Tests/BatteryCoreTests/BatteryDecoderTests.swift" \
  "$ROOT/Tests/BatteryCoreTests/StandaloneRunner.swift" -o "$OUT/battery-core-tests"
run_test_binary "$OUT/battery-core-tests"
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
  run_test_binary "$OUT/$bin"
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
run_test_binary "$OUT/battery-ui-tests"
