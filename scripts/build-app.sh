#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
bash "$ROOT/scripts/build-direct.sh"
# Validate a new bundle before replacing the old one. Keep one temporary recovery copy.
python3 - "$ROOT" <<'PY'
import os, pathlib, plistlib, shutil, subprocess, sys, tempfile
root = pathlib.Path(sys.argv[1]).resolve()
dist = root / 'dist'
dist.mkdir(exist_ok=True)
app = dist / 'LocalMonitor.app'
backup = root / '.build/previous-app/LocalMonitor.app'
with (root / 'Resources/Info.plist').open('rb') as f:
    identifier = plistlib.load(f)['CFBundleIdentifier']
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
    shutil.copy2(root / '.build/direct/LocalMonitor', new / 'Contents/MacOS/LocalMonitor')
    shutil.copy2(root / 'Resources/Info.plist', new / 'Contents/Info.plist')
    subprocess.run(['plutil', '-lint', str(new / 'Contents/Info.plist')], check=True)
    subprocess.run(['strip', '-x', str(new / 'Contents/MacOS/LocalMonitor')], check=True)
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
    print(f'Built local ad-hoc signed app: {app}')
except BaseException:
    if not app.exists() and backup.exists():
        assert backup.resolve() == root / '.build/previous-app/LocalMonitor.app'
        os.replace(backup, app)
    raise
finally:
    assert stage.resolve().parent == dist.resolve() and stage.name.startswith('.stage-')
    shutil.rmtree(stage)
PY
