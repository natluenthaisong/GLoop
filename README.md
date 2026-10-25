# GLoop

A macOS video player for guitar practice. Open a local video, select a phrase,
and repeat it at your chosen speed.

## Features

- A/B loops and 5, 10, 30, 50 or unlimited plays.
- Audio waveform with draggable loop markers, a playhead, and loop zoom.
- Pitch-preserving playback at 25–125% speed.
- Pitch transposition in semitones (−12 to +12), saved per clip.
- Automatic increases of 1 or 5 percentage points per loop, up to 100%.
- Buffered audio loops without a video-seek pause between repeats.
- Local BPM estimation, manual BPM entry and half/double-time correction.
- Metronome that follows playback speed, with adjustable beat alignment.
- Searchable local library and settings saved per clip.
- Local practice time, completed loops, speed history and manual clean marks with Undo.
- Optional ACP agent connection for trim suggestions, with opt-in loop audio sharing.
- Export the current loop to a separate MP4 at original speed and pitch.
- Dark, light and system appearance.
- Import `.gloop` practice files from Chrome, download the YouTube video or select
  an existing copy, and continue with the same loop and speed settings.

## Download

Download the [GLoop 3.4.0 preview for Apple Silicon](https://github.com/natluenthaisong/GLoop/releases/tag/v3.4.0-rc.1).
It includes the waveform editor, pitch shifting, practice stats and optional AI trim.
The Mac app is Developer ID signed but **not notarized**, so macOS may block its
first launch after downloading. This is a pre-release; the previous stable release
remains available from [GitHub Releases](https://github.com/natluenthaisong/GLoop/releases/latest).

The ZIP contains an empty library and no media, personal settings or AI agent
configuration. See [installation instructions](docs/INSTALL.md) for requirements
and signing status. The release also includes the optional unpacked Chrome extension.

## Requirements

- Apple Silicon Mac, macOS 13 or later.
- MP4, M4V or MOV supported by macOS; H.264/HEVC video with AAC audio is recommended.
  Playback, buffered loops, BPM detection and the metronome need no additional
  software or internet connection.
- Optional: FFmpeg for **File → Convert Video to MP4…**, including MKV/WebM imports.
  Conversion creates a separate copy.
- Optional: yt-dlp and FFmpeg for YouTube downloads. External tools are located
  at `/opt/homebrew/bin` or `/usr/local/bin`.

The [Chrome extension](extension/README.md) provides A/B loops and speed control
on YouTube. Building the Mac app from source additionally requires Apple's
command-line developer tools (`xcode-select --install`) and Python 3.

## Build

```sh
python3 build.py
open dist/GLoop.app
```

The default development build is ad-hoc signed. A distribution build can use
`--sign-identity` with a Developer ID Application identity. Signing alone does
not notarize the app. No VLC or other third-party libraries are linked.

To build into `~/Applications/GLoop.app`, quit an existing GLoop first, then run:

```sh
python3 build.py --install
```

A fresh build has an empty library. Use **Open video…** or drag a video into the
player. Media stays in its original location. Allow file access when macOS asks.

An optional local library JSON can be supplied with `--library Library.local.json`.
It is an array of objects with `title`, `song`, absolute `path`, and `duration`
(in seconds) fields. Local libraries and media are excluded by `.gitignore`.

## AI trim

**Ask AI…** connects to a separately installed ACP agent. Ask for a loop boundary,
review the suggested times, then choose **Use loop** or **Undo loop change**.
**Export current loop…** saves a new MP4. Audio sharing is off by default; an
agent and its model provider may require their own sign-in and fees.
See [AI Trim setup and privacy](docs/AI-TRIM.md).

## Practice

The [Chrome extension](extension/README.md) can **Save for Mac…**. Open the
resulting `.gloop` file in GLoop 2.3 or later, then choose **Download** or
**Choose video…**. Downloading requires separately installed yt-dlp and FFmpeg
(`brew install yt-dlp ffmpeg`). Full videos and a copy of the practice file are
saved under `~/Movies/GLoop`. No browser cookies are read. Unavailable or
restricted videos may fail to download; existing local videos still work.

1. Select a clip and set the speed.
2. Drag across the waveform to select a loop, then drag **A** or **B** to refine it.
   **Zoom to loop** enlarges the selection; **Fit clip** shows the whole recording.
   You can also seek and press **A/B**, or edit the times as `m:ss.mmm`.
   **Whole clip** clears the markers.
3. Enable **Repeat**, choose the play count, and press **Space**.
4. Enable **Auto speed** for +1% or +5% per new loop. For example, 75 → 76 → 77.
5. Enter or detect the original BPM, then enable the metronome. Its tempo follows
   playback speed. Expand **Beat alignment** to set a known beat position.

Use **Pitch − / +** to change the audio one semitone (half step) at a time:
**−1** lowers E to E♭; **+1** raises E♭ to E. **Reset** restores the original pitch.
Pitch is independent of speed, auto speed, loop timing and the metronome. The
video's printed tablature stays unchanged. Each clip remembers its pitch setting.
Pitch controls are available after buffered audio loads; regular playback of
videos over 20 minutes or videos without decodable audio has no pitch shifting.

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
| Command + J | Practice stats |

Open **Practice stats…** below the transport (or **View → Practice Stats**) for
all-clip or current-clip totals, today's time, sessions, speed history and completed
loops. Time counts only while media advances; pauses, stalls and seeks are excluded.
A full A–B pass counts as one loop. A partial pass after seeking does not count.
**Played cleanly** marks the most recently completed loop at its recorded speed;
**Undo** removes your most recent clean mark, even after another loop finishes. This is a manual assessment, not pitch or timing analysis.
Manual speed changes within a loop are shown as a speed range.

History begins with version 3.1. It is stored only in
`~/Library/Application Support/GLoop/PracticeStats.json`, independently of clip
settings. GLoop checkpoints it every 10 seconds, on pause and clean marks, when
changing clips, and on quit. A crash may lose the most recent unsaved seconds.
A new session starts when changing clips, restarting GLoop, or resuming after five
minutes without playback. The history tables show the latest 300 entries; totals
include all entries. Removing a clip from the library keeps its practice history.
No accounts, telemetry or uploads are used for practice stats.

Settings and imported file paths are stored in
`~/Library/Application Support/GLoop/State.json`. GLoop reads legacy
Riff Practice settings when no GLoop settings exist. No media is uploaded.
The last readable settings file is retained as `State.backup.json`. If settings
are damaged, GLoop preserves the unreadable file and attempts backup recovery.
**File → Remove from Library** removes an entry without deleting its video.

## Playback limits

Audio clips up to 20 minutes are decoded once and queued in memory. Repeats do
not seek the audio node. Short edge ramps reduce clicks without adding a pause.
Silence inside the recording remains; trim it with A/B markers. Video still seeks,
so it may briefly freeze at a boundary. Longer files or failed audio preparation
fall back to native video-player audio and may have a loop gap. Videos without
an audio track can still play. A 20-minute stereo buffer uses approximately
460 MB before the active phrase buffer; shorter practice sections use less memory.

BPM detection estimates a fixed tempo from up to 90 seconds of audio. Solos,
short clips and changing tempos can produce inaccurate or half-time estimates.
Correct the value manually when needed. Metronome and video synchronization are
approximate and affected by playback/device latency.

## Performance

Loop buffers are reused when their boundaries stay the same. Seeking copies only
a 32-frame onset and retains a view of the prepared phrase. Initial phrase copying
runs on the decoder queue. See [measured results](docs/PERFORMANCE.md) and the
profiling scripts for the Swift/native/Rust comparison.

## Verification

After building:

```sh
dist/GLoop.app/Contents/MacOS/GLoop --self-test
dist/GLoop.app/Contents/MacOS/GLoop --handoff-test
dist/GLoop.app/Contents/MacOS/GLoop --state-test
dist/GLoop.app/Contents/MacOS/GLoop --stats-test
dist/GLoop.app/Contents/MacOS/GLoop --pitch-test
dist/GLoop.app/Contents/MacOS/GLoop --media-test /absolute/path/to/test.mp4
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

Build without `--library`, then run `python3 scripts/package_release.py` for a
candidate ZIP. The packager rejects a nonempty library, unexpected app files,
personal build paths and external shared-library dependencies. Only the app,
installation instructions, license and dependency notices go into the ZIP.
The `--public` option additionally requires Developer ID signing, a valid stapled
notarization ticket and Gatekeeper acceptance. See [release checks](docs/RELEASE.md).
