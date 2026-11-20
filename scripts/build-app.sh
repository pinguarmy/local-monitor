#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
usage() {
  printf 'Usage: bash scripts/build-app.sh [--universal]\n'
  printf '  (default)    app for the host architecture (or LOCAL_MONITOR_ARCH), from .build/direct[-<arch>]\n'
  printf '  --universal  arm64 + x86_64 app; also writes .build/universal/local-monitor-cli\n'
  printf 'LOCAL_MONITOR_ICON_PREVIEW=1 (or an existing .build/previews) also writes .build/previews/app-icon.png\n'
}
UNIVERSAL=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --universal) UNIVERSAL=1 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done
HOST_ARCH="$(uname -m)"
case "$HOST_ARCH" in arm64|x86_64) ;; *) printf 'Unsupported host architecture: %s\n' "$HOST_ARCH" >&2; exit 1 ;; esac
SDK="$(xcrun --show-sdk-path)"
if [ -L "$ROOT/.build" ]; then
  printf 'Refusing to build into a symlinked .build directory\n' >&2
  exit 1
fi

# Fail unless FILE contains exactly the given architectures (order-insensitive).
require_archs() {
  local file="$1" actual expected
  shift
  actual="$(lipo -archs "$file" | tr ' ' '\n' | sed '/^$/d' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"
  expected="$(printf '%s\n' "$@" | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"
  if [ "$actual" != "$expected" ]; then
    printf '%s: expected architectures [%s], found [%s]\n' "$file" "$expected" "$actual" >&2
    exit 1
  fi
}

# App icon: draw the iconset with a small AppKit program (compiled into .build, never the
# source tree) and convert it with iconutil. Any failure stops the build.
ICON_WORK="$ROOT/.build/app-icon"
ICONSET="$ICON_WORK/AppIcon.iconset"
ICNS="$ICON_WORK/AppIcon.icns"
if [ -L "$ICON_WORK" ] || [ -L "$ICONSET" ]; then
  printf 'Refusing a symlinked icon work directory: %s\n' "$ICON_WORK" >&2
  exit 1
fi
mkdir -p "$ICON_WORK/module-cache"
xcrun swiftc -swift-version 5 -O -parse-as-library -sdk "$SDK" -target "$HOST_ARCH-apple-macosx13.0" \
  -module-cache-path "$ICON_WORK/module-cache" -framework AppKit \
  "$ROOT/scripts/make-app-icon.swift" -o "$ICON_WORK/make-app-icon"
rm -rf "$ICONSET"
rm -f "$ICNS"
mkdir "$ICONSET"
"$ICON_WORK/make-app-icon" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$ICNS"
PREVIEWS="$ROOT/.build/previews"
if [ "${LOCAL_MONITOR_ICON_PREVIEW:-}" = 1 ] || [ -d "$PREVIEWS" ]; then
  if [ -L "$PREVIEWS" ]; then
    printf 'Refusing a symlinked previews directory: %s\n' "$PREVIEWS" >&2
    exit 1
  fi
  mkdir -p "$PREVIEWS"
  cp -f "$ICONSET/icon_256x256.png" "$PREVIEWS/app-icon.png"
  printf 'App icon preview: %s\n' "$PREVIEWS/app-icon.png"
fi

if [ "$UNIVERSAL" = 1 ]; then
  # Explicit architectures build into .build/direct-arm64 and .build/direct-x86_64.
  LOCAL_MONITOR_ARCH=arm64 bash "$ROOT/scripts/build-direct.sh"
  LOCAL_MONITOR_ARCH=x86_64 bash "$ROOT/scripts/build-direct.sh"
  UNIVERSAL_OUT="$ROOT/.build/universal"
  mkdir -p "$UNIVERSAL_OUT"
  for name in LocalMonitor local-monitor-cli; do
    require_archs "$ROOT/.build/direct-arm64/$name" arm64
    require_archs "$ROOT/.build/direct-x86_64/$name" x86_64
    rm -f "$UNIVERSAL_OUT/$name.partial"
    lipo -create "$ROOT/.build/direct-arm64/$name" "$ROOT/.build/direct-x86_64/$name" \
      -output "$UNIVERSAL_OUT/$name.partial"
    require_archs "$UNIVERSAL_OUT/$name.partial" arm64 x86_64
    mv -f "$UNIVERSAL_OUT/$name.partial" "$UNIVERSAL_OUT/$name"
  done
  printf 'Universal command line tool: %s\n' "$UNIVERSAL_OUT/local-monitor-cli"
  APP_EXECUTABLE="$UNIVERSAL_OUT/LocalMonitor"
  EXPECTED_ARCHS="arm64 x86_64"
else
  bash "$ROOT/scripts/build-direct.sh"
  # Same selection build-direct.sh just used (host architecture unless LOCAL_MONITOR_ARCH is set).
  source "$ROOT/scripts/direct-arch.sh"
  require_archs "$OUT/LocalMonitor" "$ARCH"
  APP_EXECUTABLE="$OUT/LocalMonitor"
  EXPECTED_ARCHS="$ARCH"
fi

# Validate a new bundle before replacing the old one. Keep one temporary recovery copy.
python3 - "$ROOT" "$APP_EXECUTABLE" "$ICNS" "$EXPECTED_ARCHS" <<'PY'
import os, pathlib, plistlib, shutil, subprocess, sys, tempfile
root = pathlib.Path(sys.argv[1]).resolve()
executable = pathlib.Path(sys.argv[2])
icns = pathlib.Path(sys.argv[3])
expected_archs = sorted(sys.argv[4].split())
dist = root / 'dist'
dist.mkdir(exist_ok=True)
app = dist / 'LocalMonitor.app'
backup = root / '.build/previous-app/LocalMonitor.app'
with (root / 'Resources/Info.plist').open('rb') as f:
    info = plistlib.load(f)
identifier = info['CFBundleIdentifier']
# The bundle must never reference an icon it does not contain.
icon_name = info.get('CFBundleIconFile')
if icon_name != 'AppIcon':
    raise SystemExit('Resources/Info.plist must set CFBundleIconFile to AppIcon')
if icns.is_symlink() or not icns.is_file() or icns.read_bytes()[:4] != b'icns':
    raise SystemExit(f'Missing or invalid generated icon: {icns}')
if executable.is_symlink() or not executable.is_file():
    raise SystemExit(f'Missing app executable: {executable}')
if app.exists():
    if app.is_symlink() or app.resolve() != app:
        raise SystemExit('Refusing to replace a symlinked bundle')
    with (app / 'Contents/Info.plist').open('rb') as f:
        if plistlib.load(f).get('CFBundleIdentifier') != identifier:
            raise SystemExit('Refusing to replace an unrelated bundle')
if backup.exists():
    subprocess.run(['codesign', '--verify', '--strict', str(backup)], check=True)
stage = pathlib.Path(tempfile.mkdtemp(prefix='.stage-', dir=dist))
try:
    new = stage / 'LocalMonitor.app'
    (new / 'Contents/MacOS').mkdir(parents=True)
    (new / 'Contents/Resources').mkdir()
    shutil.copy2(executable, new / 'Contents/MacOS/LocalMonitor')
    shutil.copy2(root / 'Resources/Info.plist', new / 'Contents/Info.plist')
    subprocess.run(['plutil', '-lint', str(new / 'Contents/Info.plist')], check=True)
    # Localized bundle names only; UI strings are compiled into the executable.
    localizations = sorted((root / 'Resources').glob('*.lproj'))
    if not localizations:
        raise SystemExit('No Resources/*.lproj directories found')
    for lproj in localizations:
        strings = lproj / 'InfoPlist.strings'
        if lproj.is_symlink() or not strings.is_file() or strings.is_symlink():
            raise SystemExit(f'Expected a regular {lproj.name}/InfoPlist.strings')
        subprocess.run(['plutil', '-lint', str(strings)], check=True)
        (new / 'Contents/Resources' / lproj.name).mkdir()
        shutil.copy2(strings, new / 'Contents/Resources' / lproj.name / 'InfoPlist.strings')
    # All resources are in place before signing; the signature seals them.
    shutil.copy2(icns, new / 'Contents/Resources' / f'{icon_name}.icns')
    subprocess.run(['strip', '-x', str(new / 'Contents/MacOS/LocalMonitor')], check=True)
    archs = sorted(subprocess.check_output(['lipo', '-archs', str(new / 'Contents/MacOS/LocalMonitor')], text=True).split())
    if archs != expected_archs:
        raise SystemExit(f'Expected architectures {expected_archs}, found {archs}')
    subprocess.run(['codesign', '--force', '--sign', '-', str(new)], check=True)
    subprocess.run(['codesign', '--verify', '--strict', '--verbose=2', str(new)], check=True)
    if app.exists():
        assert app.resolve() == root / 'dist/LocalMonitor.app'
        if not backup.exists():
            backup.parent.mkdir(parents=True, exist_ok=True)
            assert backup.parent.resolve() == root / '.build/previous-app'
            shutil.copytree(app, backup)
        # New bundle and one original recovery copy are both verified before removal.
        shutil.rmtree(app)
    assert new.resolve() == stage.resolve() / 'LocalMonitor.app'
    os.replace(new, app)
    print(f'Built local ad-hoc signed app ({" + ".join(archs)}): {app}')
except BaseException:
    if not app.exists() and backup.exists():
        assert backup.resolve() == root / '.build/previous-app/LocalMonitor.app'
        os.replace(backup, app)
    raise
finally:
    assert stage.resolve().parent == dist.resolve() and stage.name.startswith('.stage-')
    shutil.rmtree(stage)
PY
