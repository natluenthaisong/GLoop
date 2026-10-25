#!/usr/bin/env python3
"""Package only the allowlisted app files and public notices."""
import hashlib
import json
import plistlib
import re
import stat
import subprocess
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / 'dist/GLoop.app'
APP_FILES = {
    'Contents/Info.plist',
    'Contents/MacOS/GLoop',
    'Contents/Resources/Library.json',
    'Contents/Resources/GLoop.icns',
    'Contents/_CodeSignature/CodeResources',
}


def main():
    actual = {str(p.relative_to(APP)) for p in APP.rglob('*') if p.is_file()}
    if actual != APP_FILES or any(p.is_symlink() for p in APP.rglob('*')):
        raise SystemExit('Unexpected app contents; rebuild in a clean dist directory.')
    if json.loads((APP / 'Contents/Resources/Library.json').read_text()) != []:
        raise SystemExit('Release library must be empty. Build without --library.')
    executable = APP / 'Contents/MacOS/GLoop'
    data = executable.read_bytes()
    for pattern in [rb'/Users/[^/\x00]+/', rb'gh[pousr]_[A-Za-z0-9]{20,}',
                    rb'github_pat_[A-Za-z0-9_]{20,}', rb'BEGIN [A-Z ]*PRIVATE KEY']:
        if re.search(pattern, data):
            raise SystemExit('Private path or credential pattern in executable.')
    arch = subprocess.check_output(['lipo', '-archs', str(executable)], text=True).strip()
    if arch != 'arm64':
        raise SystemExit('This release package is configured for Apple Silicon only.')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(APP)], check=True)
    version = plistlib.loads((APP / 'Contents/Info.plist').read_bytes())['CFBundleShortVersionString']
    output = ROOT / 'dist/releases'
    output.mkdir(exist_ok=True)
    archive = output / f'GLoop-{version}-macOS-arm64.zip'
    with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED) as z:
        for relative in sorted(APP_FILES):
            z.write(APP / relative, 'GLoop.app/' + relative)
        for source, name in [('docs/INSTALL.md', 'INSTALL.md'), ('LICENSE', 'LICENSE'),
                             ('THIRD_PARTY_NOTICES.md', 'THIRD_PARTY_NOTICES.md')]:
            z.write(ROOT / source, name)
    with zipfile.ZipFile(archive) as z:
        assert z.testzip() is None
        assert json.loads(z.read('GLoop.app/Contents/Resources/Library.json')) == []
        assert (z.getinfo('GLoop.app/Contents/MacOS/GLoop').external_attr >> 16) & stat.S_IXUSR
        assert len(z.namelist()) == len(APP_FILES) + 3
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    (output / 'SHA256SUMS.txt').write_text(f'{digest}  {archive.name}\n')
    print(archive)
    print(f'SHA256: {digest}')
    print('Verified: empty library, allowlisted files, executable permissions, signature, no personal path patterns.')


if __name__ == '__main__':
    main()
