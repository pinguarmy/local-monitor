#!/usr/bin/env python3
"""Fail closed on common private files, absolute home paths, and credential shapes.
This is a release guard, not a guarantee that arbitrary personal information is detected.
"""
from pathlib import Path
import re
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
excluded = {'.git', '.build', 'dist', 'evidence'}
patterns = [
    re.compile(rb'/(?:Users|home)/[A-Za-z0-9_.-]+/'),
    re.compile(rb'(?:gh[pousr]_[A-Za-z0-9]{28,}|github_pat_[A-Za-z0-9_]{30,})'),
    re.compile(rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),
]
issues = []
count = 0
for path in root.rglob('*'):
    rel = path.relative_to(root)
    if set(rel.parts) & excluded:
        continue
    if path.is_symlink():
        issues.append(f'{rel}: symlink not allowed in public source')
        continue
    if not path.is_file():
        continue
    count += 1
    if path.name in {'.env', 'hosts.yml', '.netrc', 'ObservedNoDevice.json'} or path.suffix in {'.pem', '.key', '.p12', '.pfx', '.png', '.jpg', '.sqlite', '.db'}:
        issues.append(f'{rel}: private or unreviewed artifact type')
    data = path.read_bytes()
    if any(pattern.search(data) for pattern in patterns):
        issues.append(f'{rel}: credential or absolute home-path pattern')

app = root / 'dist/LocalMonitor.app'
if app.exists():
    for path in app.rglob('*'):
        if path.is_file():
            data = path.read_bytes()
            if any(pattern.search(data) for pattern in patterns):
                issues.append(f'{path.relative_to(root)}: private path or credential pattern')
    result = subprocess.run(['codesign', '--verify', '--strict', str(app)], capture_output=True)
    if result.returncode:
        issues.append('Application signature verification failed')
if issues:
    print('\n'.join(issues), file=sys.stderr)
    sys.exit(1)
print(f'Privacy guard: {count} source files checked; no matching private files, credential shapes, or absolute home paths.')
if app.exists():
    print('Application files checked; signature valid.')
