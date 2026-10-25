#!/usr/bin/env python3
"""Build the standalone native GLoop Mac application."""
import argparse
import json
import plistlib
import platform
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SOURCES = ['NativeVideo.swift', 'ReleaseTests.swift', 'PracticeCore.swift', 'PracticeHandoff.swift', 'VideoDownload.swift', 'BPMDetector.swift', 'Metronome.swift',
           'PracticeStats.swift', 'PracticeStatsUI.swift', 'PracticeStatsTests.swift', 'PitchTests.swift', 'Waveform.swift', 'WaveformTests.swift', 'ACPClient.swift', 'AITrim.swift', 'AITrimUI.swift', 'ACPTests.swift', 'GaplessAudio.swift', 'GLoopUI.swift', 'main.swift']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--install', action='store_true', help='Build into ~/Applications instead of dist/')
    parser.add_argument('--library', type=Path, help='Optional local library JSON (no media is copied)')
    parser.add_argument('--sign-identity', default='-', help='Developer ID Application identity; default is ad-hoc for development')
    args = parser.parse_args()
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
    (resources / 'LICENSE').write_bytes((ROOT / 'LICENSE').read_bytes())
    subprocess.run(['swiftc', '-swift-version', '5', '-O',
                    '-target', platform.machine() + '-apple-macos13.0',
                    '-file-prefix-map', str(ROOT) + '=/GLoop',
                    '-debug-prefix-map', str(ROOT) + '=/GLoop', '-framework', 'AppKit', '-framework', 'AVFoundation',
                    *[str(ROOT / source) for source in SOURCES], '-o', str(executable)], check=True)
    iconset = ROOT / 'dist/GLoop.iconset'
    subprocess.run(['swift', str(ROOT / 'make-icon.swift'), str(iconset)], check=True)
    subprocess.run(['iconutil', '-c', 'icns', str(iconset), '-o', str(resources / 'GLoop.icns')], check=True)
    (app / 'Contents/Info.plist').write_bytes(plistlib.dumps(dict(
        CFBundleIdentifier='local.gloop.player', CFBundleName='GLoop', CFBundleDisplayName='GLoop',
        CFBundleExecutable='GLoop', CFBundlePackageType='APPL', CFBundleShortVersionString='3.4.0', CFBundleVersion='30400',
        CFBundleIconFile='GLoop.icns', LSMinimumSystemVersion='13.0', NSHighResolutionCapable=True,
        NSHumanReadableCopyright='Copyright © 2026 GLoop contributors. MIT licensed.',
        CFBundleDocumentTypes=[dict(CFBundleTypeName='GLoop Practice', CFBundleTypeRole='Viewer',
                                    LSHandlerRank='Owner', LSItemContentTypes=['local.gloop.practice']),
                               dict(CFBundleTypeName='Video', CFBundleTypeRole='Viewer', LSHandlerRank='Alternate',
                                    LSItemContentTypes=['public.mpeg-4', 'com.apple.quicktime-movie'])],
        UTExportedTypeDeclarations=[dict(UTTypeIdentifier='local.gloop.practice', UTTypeDescription='GLoop Practice',
                                        UTTypeConformsTo=['public.json'],
                                        UTTypeTagSpecification={'public.filename-extension': ['gloop']})],
        NSPrincipalClass='NSApplication')))
    signing = ['codesign', '--force', '--options', 'runtime', '--sign', args.sign_identity]
    if args.sign_identity != '-': signing.append('--timestamp')
    subprocess.run(signing + [str(app)], check=True)
    print(app)


if __name__ == '__main__':
    main()
