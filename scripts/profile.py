#!/usr/bin/env python3
"""Profile production Swift kernels in separate processes. Reports omit media paths."""
import argparse
import json
import platform
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--source', type=Path, default=ROOT)
p.add_argument('--output', type=Path, required=True)
p.add_argument('--runs', type=int, default=5)
p.add_argument('--media', nargs=2, action='append', metavar=('LABEL', 'PATH'), required=True)
a = p.parse_args()
a.output.mkdir(parents=True, exist_ok=True)
exe = a.output.resolve() / 'profile'
subprocess.run(['swiftc', '-O', '-swift-version', '5', '-target', platform.machine() + '-apple-macos13.0',
    *[str(a.source / f) for f in ['NativeVideo.swift', 'GaplessAudio.swift', 'BPMDetector.swift']],
    str(ROOT / 'scripts/profile/main.swift'), '-o', str(exe)], check=True)
rows = []
for label, path in a.media:
    for mode in ['prepare', 'bpm', 'fingerprint']:
        for repeat in range(1 if mode == 'fingerprint' else a.runs):
            result = subprocess.run([str(exe), mode, path], capture_output=True, text=True, check=True)
            row = dict(label=label, mode=mode, run=repeat, **json.loads(result.stdout))
            rows.append(row)
            print(json.dumps(row), flush=True)
(a.output / 'results.json').write_text(json.dumps(rows, indent=2) + '\n')
