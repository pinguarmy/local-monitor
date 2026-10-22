#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
python3 - "$ROOT" <<'PY'
import os, pathlib, plistlib, shutil, subprocess, sys, tempfile
root = pathlib.Path(sys.argv[1]).resolve()
source = root / 'dist/LocalMonitor.app'
apps = pathlib.Path.home() / 'Applications'
apps.mkdir(exist_ok=True)
target = apps / 'LocalMonitor.app'
backup = root / '.build/previous-installed-app/LocalMonitor.app'
with (source / 'Contents/Info.plist').open('rb') as f:
    identifier = plistlib.load(f)['CFBundleIdentifier']
subprocess.run(['codesign', '--verify', '--strict', str(source)], check=True)
if subprocess.run(['pgrep', '-x', 'LocalMonitor'], stdout=subprocess.DEVNULL).returncode == 0:
    raise SystemExit('LocalMonitor is running. Quit it before installing; no process was stopped.')
if target.exists():
    if target.is_symlink():
        raise SystemExit('Refusing to replace a symlinked app')
    with (target / 'Contents/Info.plist').open('rb') as f:
        if plistlib.load(f).get('CFBundleIdentifier') != identifier:
            raise SystemExit('Refusing to replace an unrelated app')
if backup.exists():
    raise SystemExit(f'Review the existing recovery copy first: {backup}')
stage = pathlib.Path(tempfile.mkdtemp(prefix='.battery-stage-', dir=apps))
try:
    new = stage / 'LocalMonitor.app'
    shutil.copytree(source, new)
    subprocess.run(['codesign', '--verify', '--strict', str(new)], check=True)
    if target.exists():
        backup.parent.mkdir(parents=True, exist_ok=True)
        assert target.resolve() == apps.resolve() / 'LocalMonitor.app'
        assert backup.parent.resolve() == root / '.build/previous-installed-app'
        shutil.copytree(target, backup)
        shutil.rmtree(target)
    assert new.resolve() == stage.resolve() / 'LocalMonitor.app'
    os.replace(new, target)
    print(f'Installed: {target}')
except BaseException:
    if not target.exists() and backup.exists():
        shutil.copytree(backup, target)
    raise
finally:
    assert stage.resolve().parent == apps.resolve() and stage.name.startswith('.battery-stage-')
    shutil.rmtree(stage)
PY
