#!/usr/bin/env python3
"""Package the verified app without filesystem owner names or extended attributes."""
from pathlib import Path
import hashlib
import plistlib
import stat
import subprocess
import zipfile

root = Path(__file__).resolve().parent.parent
subprocess.run(['python3', str(root / 'scripts/check-release-privacy.py')], check=True)
app = root / 'dist/LocalMonitor.app'
with (app / 'Contents/Info.plist').open('rb') as source:
    version = plistlib.load(source)['CFBundleShortVersionString']
arch = subprocess.check_output(['lipo', '-archs', str(app / 'Contents/MacOS/LocalMonitor')], text=True).strip()
if arch not in {'arm64', 'x86_64'}:
    raise SystemExit('Expected a single known architecture')
archive = root / 'dist' / f'LocalMonitor-v{version}-beta-macos-{arch}.zip'
with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as output:
    files = [(p, str(p.relative_to(app.parent))) for p in sorted(app.rglob('*')) if p.is_file()]
    files += [(root / 'LICENSE', 'LICENSE')]
    for source, name in files:
        if source.is_symlink():
            raise SystemExit('Refusing a symlink in release bundle')
        info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
        info.create_system = 3
        info.compress_type = zipfile.ZIP_DEFLATED
        mode = 0o755 if name.endswith('/MacOS/LocalMonitor') else 0o644
        info.external_attr = (stat.S_IFREG | mode) << 16
        output.writestr(info, source.read_bytes())
checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
(archive.parent / 'SHA256SUMS.txt').write_text(f'{checksum}  {archive.name}\n')
print(f'Packaged {archive.name}')
print(f'SHA256 {checksum}')
