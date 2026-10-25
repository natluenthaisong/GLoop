# GLoop

A macOS video player for guitar practice. Open a local video, select a phrase,
and repeat it at your chosen speed.

## Features

- A/B loops and 5, 10, 30, 50 or unlimited plays.
- Pitch-preserving playback at 25–125% speed.
- Automatic increases of 1 or 5 percentage points per loop, up to 100%.
- Buffered audio loops without a video-seek pause between repeats.
- Local BPM estimation, manual BPM entry and half/double-time correction.
- Metronome that follows playback speed, with adjustable beat alignment.
- Searchable local library and settings saved per clip.
- Dark, light and system appearance.

## Download

Download the Apple Silicon app from [GitHub Releases](https://github.com/natluenthaisong/GLoop/releases/latest).
The ZIP contains an empty library and no media or personal settings. VLC 3 and
FFmpeg are required separately. See [installation instructions](docs/INSTALL.md)
for requirements and the app's signing status.

## Requirements

- macOS 13 or later. Developed and tested on Apple Silicon.
- Apple's command-line developer tools (`xcode-select --install`).
- Python 3.
- [VLC 3](https://www.videolan.org/vlc/) installed at `/Applications/VLC.app`.
  Its headers and libraries must be present. VLC 4 is not supported.
- [FFmpeg](https://ffmpeg.org/download.html) at `/opt/homebrew/bin/ffmpeg`
  or `/usr/local/bin/ffmpeg` for buffered audio and BPM detection.
  Homebrew users can install it with `brew install ffmpeg`.

VLC must match the architecture of the Swift compiler's build target.

## Build

```sh
python3 build.py
open dist/GLoop.app
```

The build is locally ad-hoc signed, not notarized. It dynamically loads the
installed VLC libraries; keep VLC at the path above.

To build into `~/Applications/GLoop.app`, quit an existing GLoop first, then run:

```sh
python3 build.py --install
```

A fresh build has an empty library. Use **Open video…** or drag a video into the
player. Media stays in its original location. Allow file access when macOS asks.

An optional local library JSON can be supplied with `--library Library.local.json`.
It is an array of objects with `title`, `song`, absolute `path`, and `duration`
(in seconds) fields. Local libraries and media are excluded by `.gitignore`.

## Practice

1. Select a clip and set the speed.
2. Seek and press **A** for the loop start, then **B** for the end. You can also
   edit the times as `m:ss.mmm`. **Whole clip** clears the markers.
3. Enable **Repeat**, choose the play count, and press **Space**.
4. Enable **Auto speed** for +1% or +5% per new loop. For example, 75 → 76 → 77.
5. Enter or detect the original BPM, then enable the metronome. Its tempo follows
   playback speed. Expand **Beat alignment** to set a known beat position.

The play count includes the first play. Playback pauses at the target; press
Space to restart. Video and metronome volume are independent.

| Key | Action |
| --- | --- |
| Space | Play / pause / restart |
| A / B | Set loop start / end |
| [ / ] | Speed down / up by 5 percentage points |
| 0 | Normal speed |
| Left / Right | Seek one second |
| Shift + Left / Right | Seek five seconds |
| L | Toggle repeat |
| N / P | Next / previous clip |
| Command + O | Open video |
| Command + F | Full screen |

Settings and imported file paths are stored in
`~/Library/Application Support/GLoop/State.json`. GLoop reads legacy
Riff Practice settings when no GLoop settings exist. No media is uploaded.

## Playback limits

Audio clips up to 20 minutes are decoded once and queued in memory. Repeats do
not seek the audio node. Short edge ramps reduce clicks without adding a pause.
Silence inside the recording remains; trim it with A/B markers. Video still uses
VLC seeks, so it may briefly freeze at a boundary. Longer files or failed audio
preparation fall back to VLC and may have a loop gap.

BPM detection estimates a fixed tempo from up to 90 seconds of audio. Solos,
short clips and changing tempos can produce inaccurate or half-time estimates.
Correct the value manually when needed. Metronome and video synchronization are
approximate and affected by playback/device latency.

## Verification

After building:

```sh
dist/GLoop.app/Contents/MacOS/GLoop --self-test
dist/GLoop.app/Contents/MacOS/GLoop --bpm-test
dist/GLoop.app/Contents/MacOS/GLoop --metronome-test
dist/GLoop.app/Contents/MacOS/GLoop --gapless-test
```

These check settings, loop counts, BPM estimation, metronome timing, and offline
rendered audio across loop joins. A muted integration check requires a local video
with at least two seconds of audio:

```sh
dist/GLoop.app/Contents/MacOS/GLoop --smoke-ramp1 --smoke-file /absolute/path/to/video.mp4
```

It opens a window, plays five short loops at 90–94%, checks video output and
metronome scheduling, then exits. Inspect `success` in
`~/Library/Application Support/GLoop/smoke-ramp1.json`. Use `--smoke-ramp` for the
5% progression or `--smoke-test` for fixed-speed playback. Smoke tests do not
save clip settings.

## License

[MIT](LICENSE). Third-party dependencies retain their own licenses; see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). No practice media is included.

## Package a release

Build without `--library`, then run `python3 scripts/package_release.py`.
The packager rejects a nonempty library, unexpected app files and personal build
paths. It creates a ZIP and SHA-256 checksum in `dist/releases/`. Only the app,
installation instructions, license and dependency notices go into the ZIP.
