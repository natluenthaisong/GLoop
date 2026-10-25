#!/usr/bin/env python3
"""Build GLoop using a separately installed VLC 3 application."""
import argparse
import json
import plistlib
import platform
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent
VLC = Path('/Applications/VLC.app/Contents/MacOS')
SOURCES = ['PracticeCore.swift', 'BPMDetector.swift', 'Metronome.swift',
           'GaplessAudio.swift', 'GLoopUI.swift', 'main.swift']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--install', action='store_true', help='Build into ~/Applications instead of dist/')
    parser.add_argument('--library', type=Path, help='Optional local library JSON (no media is copied)')
    args = parser.parse_args()
    if not (VLC / 'include/vlc/vlc.h').exists() or not (VLC / 'lib/libvlc.dylib').exists():
        parser.error('Install VLC 3 at /Applications/VLC.app, including its headers and libraries.')
    library = []
    if args.library:
        library = json.loads(args.library.expanduser().read_text())
        if not isinstance(library, list) or any(not isinstance(c, dict) or
                not all(k in c for k in ('title', 'song', 'path', 'duration')) for c in library):
            parser.error('Library JSON must be an array of title, song, path and duration objects.')
    app = (Path.home() / 'Applications' if args.install else ROOT / 'dist') / 'GLoop.app'
    executable = app / 'Contents/MacOS/GLoop'
    resources = app / 'Contents/Resources'
    executable.parent.mkdir(parents=True, exist_ok=True)
    resources.mkdir(parents=True, exist_ok=True)
    (resources / 'Library.json').write_text(json.dumps(library, indent=2))
    subprocess.run(['swiftc', '-swift-version', '5', '-O',
                    '-target', platform.machine() + '-apple-macos13.0',
                    '-file-prefix-map', str(ROOT) + '=/GLoop',
                    '-debug-prefix-map', str(ROOT) + '=/GLoop', '-import-objc-header', str(ROOT / 'Bridge.h'),
                    '-I', str(VLC / 'include'), '-L', str(VLC / 'lib'), '-lvlc',
                    '-Xlinker', '-rpath', '-Xlinker', str(VLC / 'lib'), '-framework', 'AppKit',
                    *[str(ROOT / source) for source in SOURCES], '-o', str(executable)], check=True)
    iconset = ROOT / 'dist/GLoop.iconset'
    subprocess.run(['swift', str(ROOT / 'make-icon.swift'), str(iconset)], check=True)
    subprocess.run(['iconutil', '-c', 'icns', str(iconset), '-o', str(resources / 'GLoop.icns')], check=True)
    (app / 'Contents/Info.plist').write_bytes(plistlib.dumps(dict(
        CFBundleIdentifier='local.gloop.player', CFBundleName='GLoop', CFBundleDisplayName='GLoop',
        CFBundleExecutable='GLoop', CFBundlePackageType='APPL', CFBundleShortVersionString='2.2.0',
        CFBundleIconFile='GLoop.icns', LSMinimumSystemVersion='13.0', NSHighResolutionCapable=True,
        NSPrincipalClass='NSApplication')))
    subprocess.run(['codesign', '--force', '--deep', '--sign', '-', str(app)], check=True)
    print(app)


if __name__ == '__main__':
    main()
