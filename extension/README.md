# GLoop for YouTube

A small Chrome extension for practicing a phrase in a YouTube video.

- Set A and B, then repeat the phrase.
- Adjust speed from 25% to 125%, preserving pitch.
- Optionally add 1 or 5 percentage points each loop, up to 100%.
- Save a practice file for GLoop Mac to download and open the video later.

## Install

1. Download and unzip the extension package, or use this `extension` directory.
2. Open `chrome://extensions` in Chrome and enable **Developer mode**.
3. Click **Load unpacked** and select the folder containing `manifest.json`.
4. Open a regular YouTube video. Click Chrome's Extensions button, then **GLoop for YouTube**. Pin it if you want it in the toolbar.

This is an unpacked extension, not a Chrome Web Store listing. It does not need
the GLoop desktop app, VLC or FFmpeg.

## Use

Seek with YouTube's controls. Click **Set here** for A and B, or type times such
as `1:23.500`. Click **Start loop**. The loop must be at least 0.25 seconds long.
Choose a speed and, optionally, an increase per loop. YouTube's Play/Pause control
still works. **Stop loop** leaves the video playing at the chosen speed.

**Close**, Escape while focused in the panel, or clicking the extension again
stops looping and restores the speed from before GLoop was opened. A new video
clears the markers. Seeking manually stops the loop. Ads suspend the controls
and stop looping; click **Start loop** again after the ad.

## Continue on Mac

Click **Save for Mac…** to download a small `.gloop` practice file. It contains
the video's public link, title, A/B times, speed and increase setting. It does
not contain the video. You can keep this file and open it later.

Open it in **GLoop Mac 2.3 or later** (double-click, drag it onto GLoop, or choose
**File → Open Practice File…**). Choose **Download** to save the full video to
`~/Movies/GLoop`, then open it with the saved settings. The Mac needs yt-dlp and
FFmpeg installed separately: `brew install yt-dlp ffmpeg`.

Already downloaded the full video? Choose **Choose video…** instead. Use the
original full-length video so the saved timestamps match. After import, practice
works offline. Downloads can fail for unavailable or restricted videos; GLoop
does not collect browser cookies or bypass access restrictions.

## Limits

YouTube loops use the video's seek operation. There can be a brief pause or
buffering at the boundary; this extension does not provide the desktop app's
buffered audio looping. Timing can be less precise in background tabs. Keep the
video tab visible while practicing. YouTube page changes may affect compatibility.

This version is for standard `/watch` pages, not Shorts, embedded players or live
streams. It has no BPM detector, metronome, clip library or saved presets.

## Privacy and permissions

The extension makes no network requests and stores no settings or history in
Chrome. Settings stay in memory unless you explicitly export a `.gloop` file.
Exported files contain the public video link and your selected practice settings;
playlist and tracking parameters are omitted. The extension contains no media,
personal settings, account details, analytics or remote code.

`activeTab` provides temporary access when you click the extension. `scripting`
injects the controls into that tab. The extension checks for a YouTube watch page
before injecting. It requests no permanent host access, microphone access,
tab capture, browsing history or storage permissions. YouTube itself continues
to receive its normal playback traffic.

## Development

Run `node --test extension/tests/core.test.cjs` from the repository root for the
dependency-free loop tests. For DOM integration tests, run
`npm ci --prefix extension/tests` then `npm test --prefix extension/tests`.
These exercise the panel with simulated media events; they do not certify live
YouTube compatibility. Run `python3 scripts/package_extension.py` to create
a ZIP in `dist/releases/`. The packager uses an explicit list of source files;
tests, media and local state are excluded.

MIT licensed; see `LICENSE` in the package or repository root.
