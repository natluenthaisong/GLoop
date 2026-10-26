#!/usr/bin/env python3
"""Package only the allowlisted app files and public notices."""
import hashlib
import argparse
import json
import plistlib
import re
import stat
import subprocess
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / 'dist/GLoop.app'
APP_FILES = {
    'Contents/Info.plist',
    'Contents/MacOS/GLoop',
    'Contents/Resources/Library.json',
    'Contents/Resources/LICENSE',
    'Contents/Resources/GLoop.icns',
    'Contents/_CodeSignature/CodeResources',
}
# The stapled notarization ticket lives here; present only after scripts/notarize.py.
TICKET = 'Contents/CodeResources'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--public', action='store_true', help='Require Developer ID and a stapled notarization ticket')
    args = parser.parse_args()
    actual = {str(p.relative_to(APP)) for p in APP.rglob('*') if p.is_file()}
    if actual - {TICKET} != APP_FILES or any(p.is_symlink() for p in APP.rglob('*')):
        raise SystemExit('Unexpected app contents; rebuild in a clean dist directory.')
    if args.public and TICKET not in actual:
        raise SystemExit('Public release requires a stapled notarization ticket (run scripts/notarize.py).')
    files = sorted(actual)
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
    signature = subprocess.run(['codesign', '-dv', '--verbose=4', str(APP)], capture_output=True, text=True, check=True).stderr
    if args.public:
        if 'Authority=Developer ID Application:' not in signature:
            raise SystemExit('Public release requires a Developer ID Application signature.')
        subprocess.run(['xcrun', 'stapler', 'validate', str(APP)], check=True)
        subprocess.run(['spctl', '--assess', '--type', 'execute', '--verbose=2', str(APP)], check=True)
    dependencies = subprocess.check_output(['otool', '-L', str(executable)], text=True).splitlines()[1:]
    if any(not line.strip().startswith(('/System/', '/usr/lib/')) for line in dependencies):
        raise SystemExit('Release must link only to macOS system libraries.')
    version = plistlib.loads((APP / 'Contents/Info.plist').read_bytes())['CFBundleShortVersionString']
    output = ROOT / 'dist/releases'
    output.mkdir(exist_ok=True)
    suffix = '' if args.public else '-candidate'
    archive = output / f'GLoop-{version}{suffix}-macOS-arm64.zip'
    with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED) as z:
        for relative in files:
            z.write(APP / relative, 'GLoop.app/' + relative)
        for source, name in [('docs/INSTALL.md', 'INSTALL.md'), ('LICENSE', 'LICENSE'),
                             ('THIRD_PARTY_NOTICES.md', 'THIRD_PARTY_NOTICES.md')]:
            z.write(ROOT / source, name)
    with zipfile.ZipFile(archive) as z:
        assert z.testzip() is None
        assert json.loads(z.read('GLoop.app/Contents/Resources/Library.json')) == []
        assert (z.getinfo('GLoop.app/Contents/MacOS/GLoop').external_attr >> 16) & stat.S_IXUSR
        assert len(z.namelist()) == len(files) + 3
    # Validate what customers will extract, not only the original build tree.
    with tempfile.TemporaryDirectory(prefix='gloop-release-check-') as check:
        subprocess.run(['ditto', '-x', '-k', str(archive), check], check=True)
        extracted = str(Path(check) / 'GLoop.app')
        subprocess.run(['codesign', '--verify', '--deep', '--strict', extracted], check=True)
        if args.public:
            subprocess.run(['xcrun', 'stapler', 'validate', extracted], check=True)
            subprocess.run(['spctl', '--assess', '--type', 'execute', '--verbose=2', extracted], check=True)
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    (output / 'SHA256SUMS.txt').write_text(f'{digest}  {archive.name}\n')
    print(archive)
    print(f'SHA256: {digest}')
    print('Verified: empty library, allowlisted files, executable permissions, signature, system-only libraries, no personal path patterns.')


if __name__ == '__main__':
    main()
