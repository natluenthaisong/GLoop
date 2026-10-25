# Install GLoop

This download is for Apple Silicon Macs (M1 or newer), macOS 13 or later.
The build targets macOS 13 and has been tested on macOS 27; older supported
versions have not been tested on a separate machine.

1. Install the Apple Silicon version of [VLC 3](https://www.videolan.org/vlc/)
   at `/Applications/VLC.app`. GLoop loads its video engine from there.
2. Install [FFmpeg](https://ffmpeg.org/download.html) for buffered loops and BPM
   detection. With Homebrew, use `brew install ffmpeg`. GLoop looks for it at
   `/opt/homebrew/bin/ffmpeg` or `/usr/local/bin/ffmpeg`.
3. Unzip the download and drag `GLoop.app` into Applications.
4. Open GLoop, click **Open video…**, and choose your own video.

The app is ad-hoc signed, not signed with an Apple Developer ID or notarized.
macOS may block its first launch. Review
[Apple's guidance for opening downloaded apps](https://support.apple.com/en-us/102445)
before deciding whether to allow it. No security settings need to be disabled
globally.

The download contains an empty library and no songs, videos, imported file
paths, saved settings or credentials. Your own library and settings are saved
in `~/Library/Application Support/GLoop/State.json` after you use the app.
An existing installation keeps its settings.

VLC and FFmpeg are separate dependencies and are not included in the ZIP.
See `THIRD_PARTY_NOTICES.md` for their licensing information.

To verify the ZIP, place it beside `SHA256SUMS.txt` and run:

```sh
shasum -a 256 -c SHA256SUMS.txt
```
