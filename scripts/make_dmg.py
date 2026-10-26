#!/usr/bin/env python3
"""Build, sign, notarize and staple a drag-to-Applications disk image for a notarized GLoop.app.

The image contains only GLoop.app and an Applications alias. It is signed with the
same Developer ID as the app, submitted to Apple as its own notarization, stapled,
mounted and compared against the source app before its checksum is recorded in
dist/releases/SHA256SUMS.txt. In-app updates keep using the ZIP; the DMG is for
first installs.

    python3 scripts/make_dmg.py --profile GLoop            # dist/GLoop.app after scripts/notarize.py
    python3 scripts/make_dmg.py --app path/to/GLoop.app    # any stapled Developer ID build
"""
import argparse
import hashlib
import json
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'dist/releases'


def run(args, **kwargs):
    print('+', ' '.join(str(a) for a in args), flush=True)
    return subprocess.run([str(a) for a in args], check=True, text=True, **kwargs)


def signature(path):
    return subprocess.run(['codesign', '-dv', '--verbose=4', str(path)], capture_output=True, text=True, check=True).stderr


def developer_id(app):
    match = re.search(r'^Authority=(Developer ID Application: .+)$', signature(app), re.M)
    if not match:
        sys.exit('The app is not signed with a Developer ID Application certificate.')
    return match.group(1)


def record_checksum(archive):
    """Add or replace the archive's line in SHA256SUMS.txt without touching other entries."""
    sums = OUTPUT / 'SHA256SUMS.txt'
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    lines = [line for line in (sums.read_text().splitlines() if sums.exists() else []) if not line.endswith('  ' + archive.name)]
    lines.append(f'{digest}  {archive.name}')
    sums.write_text('\n'.join(lines) + '\n')
    return digest


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--app', type=Path, default=ROOT / 'dist/GLoop.app', help='Stapled Developer ID build (default: dist/GLoop.app)')
    parser.add_argument('--profile', default='GLoop', help='notarytool keychain profile name (default: GLoop)')
    parser.add_argument('--skip-notarize', action='store_true', help='Build and sign only (candidate image, not for distribution)')
    args = parser.parse_args()
    app = args.app.resolve()
    if not (app / 'Contents/MacOS/GLoop').exists():
        sys.exit(f'{app} is not a GLoop build.')
    if json.loads((app / 'Contents/Resources/Library.json').read_text()) != []:
        sys.exit('The app contains a nonempty library. Use a release build made without --library.')
    identity = developer_id(app)
    run(['codesign', '--verify', '--deep', '--strict', app])
    if not args.skip_notarize:
        run(['xcrun', 'stapler', 'validate', app])
        run(['spctl', '--assess', '--type', 'execute', '--verbose=2', app])
    version = plistlib.loads((app / 'Contents/Info.plist').read_bytes())['CFBundleShortVersionString']
    OUTPUT.mkdir(parents=True, exist_ok=True)
    suffix = '-candidate' if args.skip_notarize else ''
    image = OUTPUT / f'GLoop-{version}{suffix}-macOS-arm64.dmg'
    if image.exists():
        image.unlink()

    with tempfile.TemporaryDirectory(prefix='gloop-dmg-') as tmp:
        staging = Path(tmp) / 'staging'
        staging.mkdir()
        run(['ditto', app, staging / 'GLoop.app'])
        (staging / 'Applications').symlink_to('/Applications')
        run(['hdiutil', 'create', '-volname', f'GLoop {version}', '-srcfolder', staging, '-fs', 'HFS+',
             '-format', 'UDZO', '-imagekey', 'zlib-level=9', '-ov', '-quiet', image])
    run(['codesign', '--sign', identity, '--timestamp', '--force', image])
    run(['codesign', '--verify', '--strict', '--verbose=2', image])

    if not args.skip_notarize:
        work = ROOT / 'dist/notarize'
        work.mkdir(parents=True, exist_ok=True)
        result = run(['xcrun', 'notarytool', 'submit', image, '--keychain-profile', args.profile, '--wait', '--output-format', 'json'], capture_output=True)
        report = json.loads(result.stdout)
        (work / 'dmg-submission.json').write_text(json.dumps(report, indent=2))
        print(json.dumps(report, indent=2))
        if report.get('status') != 'Accepted':
            log = subprocess.run(['xcrun', 'notarytool', 'log', report.get('id', ''), '--keychain-profile', args.profile], capture_output=True, text=True)
            (work / 'dmg-notarization-log.json').write_text(log.stdout)
            print(log.stdout)
            sys.exit('DMG notarization was not accepted. See dist/notarize/dmg-notarization-log.json.')
        run(['xcrun', 'stapler', 'staple', image])
        run(['xcrun', 'stapler', 'validate', image])
        run(['spctl', '--assess', '--type', 'open', '--context', 'context:primary-signature', '--verbose=2', image])

    # Mount the finished image and check what the customer will drag out of it.
    mount = Path(tempfile.mkdtemp(prefix='gloop-dmg-mount-'))
    run(['hdiutil', 'attach', image, '-mountpoint', mount, '-nobrowse', '-readonly', '-quiet'])
    try:
        entries = sorted(p.name for p in mount.iterdir() if not p.name.startswith('.'))
        if entries != ['Applications', 'GLoop.app'] or Path.readlink(mount / 'Applications') != Path('/Applications'):
            sys.exit(f'Unexpected image contents: {entries}')
        run(['diff', '-r', app, mount / 'GLoop.app'])
        run(['codesign', '--verify', '--deep', '--strict', mount / 'GLoop.app'])
        if not args.skip_notarize:
            run(['xcrun', 'stapler', 'validate', mount / 'GLoop.app'])
            run(['spctl', '--assess', '--type', 'execute', '--verbose=2', mount / 'GLoop.app'])
    finally:
        run(['hdiutil', 'detach', mount, '-quiet'])
        shutil.rmtree(mount, ignore_errors=True)

    digest = hashlib.sha256(image.read_bytes()).hexdigest() if args.skip_notarize else record_checksum(image)
    print(image)
    print(f'SHA256: {digest}')
    print('Verified: signed image, app identical to source, signature' + ('' if args.skip_notarize else ', stapled tickets and Gatekeeper acceptance for image and app') + '.')


if __name__ == '__main__':
    main()
