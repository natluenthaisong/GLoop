#!/usr/bin/env python3
"""Notarize dist/GLoop.app with a stored notarytool profile, staple it and build the public ZIP.

One-time setup (credentials stay in the login keychain, never in this repository):

    xcrun notarytool store-credentials GLoop --apple-id you@example.com --team-id TEAMID

Then, after a Developer ID build (python3 build.py --sign-identity 'Developer ID Application: …'):

    python3 scripts/notarize.py --profile GLoop
"""
import argparse
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / 'dist/GLoop.app'


def run(args, **kwargs):
    print('+', ' '.join(args), flush=True)
    return subprocess.run(args, check=True, text=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--profile', default='GLoop', help='notarytool keychain profile name (default: GLoop)')
    parser.add_argument('--skip-package', action='store_true', help='Staple only; do not run the public packager')
    args = parser.parse_args()
    if not APP.exists():
        sys.exit('dist/GLoop.app is missing. Build it first without --library and with --sign-identity.')
    signature = subprocess.run(['codesign', '-dv', '--verbose=4', str(APP)], capture_output=True, text=True, check=True).stderr
    if 'Authority=Developer ID Application:' not in signature or 'flags=0x10000(runtime)' not in signature:
        sys.exit('Notarization needs a Developer ID Application signature with the hardened runtime.')
    if json.loads((APP / 'Contents/Resources/Library.json').read_text()) != []:
        sys.exit('The app contains a nonempty library. Rebuild without --library.')
    work = ROOT / 'dist/notarize'
    work.mkdir(parents=True, exist_ok=True)
    submission = work / 'GLoop-submission.zip'
    if submission.exists():
        submission.unlink()
    run(['ditto', '-c', '-k', '--keepParent', str(APP), str(submission)])
    result = run(['xcrun', 'notarytool', 'submit', str(submission), '--keychain-profile', args.profile, '--wait', '--output-format', 'json'], capture_output=True)
    report = json.loads(result.stdout)
    (work / 'submission.json').write_text(json.dumps(report, indent=2))
    print(json.dumps(report, indent=2))
    if report.get('status') != 'Accepted':
        log = subprocess.run(['xcrun', 'notarytool', 'log', report.get('id', ''), '--keychain-profile', args.profile], capture_output=True, text=True)
        (work / 'notarization-log.json').write_text(log.stdout)
        print(log.stdout)
        sys.exit('Notarization was not accepted. See dist/notarize/notarization-log.json.')
    run(['xcrun', 'stapler', 'staple', str(APP)])
    run(['xcrun', 'stapler', 'validate', str(APP)])
    run(['spctl', '--assess', '--type', 'execute', '--verbose=2', str(APP)])
    if not args.skip_package:
        run([sys.executable, str(ROOT / 'scripts/package_release.py'), '--public'])
    print('Notarized, stapled and verified.')


if __name__ == '__main__':
    main()
