# Install GLoop 3.4.0

For Apple Silicon Macs (M1 or newer), macOS 13 or later. Tested on macOS 27.0.1;
older target versions have not yet been checked on separate machines.

1. Unzip the download and drag `GLoop.app` into Applications.
2. Open GLoop, click **Open video…**, and choose an MP4, M4V or MOV.
3. Drag across the waveform to select a phrase, choose a speed, then press Space.
   Drag A/B to adjust the loop; **Zoom to loop** gives a closer view.
   The A/B time fields remain available for precise or keyboard entry.

Playback, buffered loops, BPM detection and the metronome run locally using
macOS frameworks. No VLC installation, account or activation is needed.
H.264/HEVC video with AAC audio is recommended.

## Candidate signing status

The 3.4.0 candidate is Developer ID signed but has not been notarized. It is a
testing build, not yet the public distribution build. macOS may block a download's
first launch. See [Apple's downloaded-app guidance](https://support.apple.com/en-us/102445).
Do not disable system-wide security settings.

## Your files

The ZIP includes an empty library, with no videos, personal settings, imported
paths or credentials. Opened videos remain in their original location. Allow file
access when macOS asks. An existing installation keeps its library and settings
in `~/Library/Application Support/GLoop/State.json`.

**File → Remove from Library** removes an entry without deleting its video.
Settings are saved automatically, with a readable backup in `State.backup.json`.

## Other formats and YouTube

**File → Convert Video to MP4…** creates an H.264/AAC copy in `~/Movies/GLoop`,
preserving the original. This optional feature needs FFmpeg. With Homebrew:

```sh
brew install ffmpeg
```

The Chrome extension's **Save for Mac…** creates a `.gloop` practice file. Open it
in GLoop, then choose **Download** or **Choose video…**. Downloading needs yt-dlp
and FFmpeg (`brew install yt-dlp ffmpeg`), installed at `/opt/homebrew/bin` or
`/usr/local/bin`. Downloads and their practice files go in `~/Movies/GLoop`.
Browser cookies are not imported. Unavailable or restricted videos may fail.

## Playback limits

Waveforms and pitch shifting require buffered audio.
Buffered audio supports videos up to 20 minutes. Longer videos use regular
playback, which can pause briefly between loops. Video frames can briefly freeze
at loop boundaries even with buffered audio. Silence in the recording remains.
BPM detection is an estimate; correct it manually for short or changing-tempo
passages. The metronome follows the entered tempo and playback speed.

To check download integrity, place the ZIP beside `SHA256SUMS.txt` and run:

```sh
shasum -a 256 -c SHA256SUMS.txt
```

## Optional AI trim

**Ask AI…** connects to an installed ACP v1 agent. Select its executable and ACP
arguments, then connect. Sign in through the agent’s own app or CLI first.
GLoop includes no model or AI subscription. Ask sends timing and waveform data;
audio sharing is opt-in and may reach the agent’s cloud provider. Suggestions
require **Use loop** before changing markers. **Export current loop…** saves a
separate MP4 and never overwrites the source. For setup and privacy details, see
[AI Trim](https://github.com/natluenthaisong/GLoop/blob/main/docs/AI-TRIM.md).
