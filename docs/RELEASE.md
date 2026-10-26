# GLoop 3.5.1 release

Scope: a standalone Mac guitar-practice player with reliable local playback,
A/B loops, pitch-preserving speed control, +1%/+5% progression, BPM detection,
and a synchronized metronome. No payment integration, account or activation.

## Changes

3.5.1 adds in-app updates from GitHub releases (stable, notarized releases only, verified by checksum, signature, team and notarization before an in-place swap), moves clips bundled by `--library` builds into the saved library so updates keep them, and ships the first notarized build, as a drag-to-Applications disk image for first installs and a ZIP for in-app updates. See [Updates](../README.md#updates).

3.5.0 adds direct YouTube links: paste a link with ⌘V or ⌘L (or drop it on the video), confirm Download, and the video is downloaded with yt-dlp/FFmpeg, added to the library under YouTube and opened with Repeat on; `youtu.be`, `shorts` and `embed` forms and `t=` start times are accepted, and a video already in the library opens without a second download. It also makes everyday practice faster from the keyboard: ⌘F finds a section and Return opens the first match; Return or Home goes back to A; Shift+[ and Shift+] change speed by 1% and the speed slider moves in 1% steps; C marks the last completed loop as played cleanly; Up/Down arrows nudge the A/B time fields. Full Screen moves to the standard ⌃⌘F. Pressing Space while audio loads starts playback when it is ready; missing video files are flagged in the library; long status messages show in full as tooltips. Rapid clip switching no longer waits for stale decodes, and the playback loop only updates controls whose visible value changed, roughly halving playback CPU. See [performance results](PERFORMANCE.md).

3.4.0 adds optional ACP v1 agent connections for AI trim suggestions, explicit loop application and Undo, and MP4 export to a new file. Audio sharing is opt-in and capability-gated. See [AI Trim](AI-TRIM.md) for setup, data handling and limits. No agent, AI subscription or credentials are included.

3.3.0 adds a local audio waveform with drag selection, adjustable A/B handles, a playback position, and loop zoom. Peak summaries share the existing PCM decode and stay bounded to 64 KB. Loop edits pause during the gesture and resume when released.

3.2.0 adds per-clip pitch transposition in semitone steps (−12 to +12), with one-click reset. It uses the existing audio engine independently of playback speed. Disabled controls explain when buffered audio is unavailable.

3.1.0 adds local practice time, completed loops, speed history, and manual clean marks with Undo. History is separate from clip settings and never included in app bundles. The 3.0.1 buffer-reuse and seek improvements remain; see [performance results](PERFORMANCE.md).

- Native AVFoundation video and PCM decoding replace VLC and FFmpeg in core playback.
- MP4/MOV import validates playability before adding library entries.
- Optional MKV/WebM conversion creates an H.264/AAC copy without replacing the source.
- YouTube handoff requests MP4-compatible video and audio.
- Saved settings are normalized, written atomically and backed up. Damaged files
  are preserved, with recovery from the last readable backup.
- Library entries can be removed without deleting videos; selected videos can be
  revealed in Finder. Empty-state controls and import errors are clearer.
- The package includes only the app, empty library, license and public instructions.

## Verification

ACP and trim export are tested with an offline protocol peer and synthetic media. A real authenticated model provider has not been tested; musical accuracy and agent-specific behavior need that separate validation.

The candidate was checked on Apple Silicon, macOS 27.0.1. The deployment target
is macOS 13; that minimum and other Macs still need separate-machine validation.

Automated checks cover loop counts and speed increments, legacy settings,
invalid settings, backup persistence, handoff validation, native stereo/mono
resampling, bounded audio reads, corrupt media, continuous rendered loop audio,
metronome timing, and BPM estimates. The app's muted integration checks cover
video rendering, five repeats, speed progression and metronome synchronization.
Pitch checks render E4 at −12/−1/0/+1/+12 semitones, at 100% and 75% speed; they measure output frequency, loop count/duration and audio continuity at joins.
Waveform checks cover stereo peak preservation, silence, the final partial bin, bounded storage, time mapping, zoom bounds and reversed selections. Native UI checks cover marker edits, zoom/Fit and resuming playback after selection in dark and light appearances.
Practice-stat checks cover active time, stalls, sleep, seeks, partial loops, speed attribution, clean/undo, isolated test storage and damaged-history recovery.
Optional conversion is exercised with a short MKV test fixture. Test media and
reports stay outside the release package.

The signed candidate passed both +1% and +5% five-loop integration runs.
A YouTube handoff test downloaded a native MP4 and retained its 0.4–1.2 second
loop, 75% speed and +1% increment. Native MOV decoding also passed with a
non-ASCII filename.

Manual checks cover clean first launch, native MP4 import, invalid marker input,
removing a library entry while preserving the file, and empty/loaded layouts.
The corrected empty-state message was checked in dark and light appearances.

## Build and package

```sh
python3 build.py --sign-identity 'Developer ID Application: YOUR NAME (TEAM ID)'
python3 scripts/package_release.py
```

Do not pass `--library` for distribution. The candidate ZIP name contains
`-candidate`. Packaging checks the file allowlist, empty library, executable
permissions, code signature, extracted signature, system-only linked libraries,
and private-path/credential patterns. It produces a SHA-256 checksum.

## GitHub preview

The signed candidate is published as the **v3.5.0-rc.1 pre-release** (3.4.0 was **v3.4.0-rc.1**), with its
notarization status and AI-provider testing limits stated in the release notes.
It does not replace the previous stable release. The source and download packages
exclude local media, settings, history, credentials and agent configuration.

## Notarized stable release

3.5.1 is notarized with an App Store Connect API key stored as the `GLoop`
notarytool keychain profile on the release Mac; the key itself lives outside the
repository.

After the owner configures a notarytool Keychain profile locally, run the
notarization script, which submits the app, staples the ticket, builds the
public ZIP and then runs `scripts/make_dmg.py`: a drag-to-Applications disk
image holding only the app and an Applications alias, signed with the same
Developer ID, notarized as its own submission, stapled, mounted and compared
against the source app. Do not put credentials in source or scripts.

```sh
xcrun notarytool store-credentials GLoop --apple-id you@example.com --team-id TEAMID   # once
python3 build.py --sign-identity 'Developer ID Application: YOUR NAME (TEAM ID)'
python3 scripts/notarize.py --profile GLoop
```

Publish the result as a normal (non-preview) GitHub release tagged `vX.Y.Z` with
`GLoop-X.Y.Z-macOS-arm64.dmg` (first installs), `GLoop-X.Y.Z-macOS-arm64.zip`
(in-app updates) and `SHA256SUMS.txt`, which lists both. Installed copies of
3.5.1 or later find the ZIP through **Check for Updates…**, which only accepts
stable releases with a matching checksum, the same team's signature and a valid
notarization. The 3.5.1 disk image was added to the published release from the
exact app in its ZIP.

Only publish as a stable release after notarization reports Accepted and the public packager passes.
The public packager validates stapling and Gatekeeper both before packaging and
on the extracted app. Test the final download on a clean second Mac, including
file-access permission, playback, loops and restart persistence, before shipping.

Buffered audio is limited to 20-minute videos; video seeks can briefly freeze.
BPM is an estimate, and optional YouTube downloads depend on external tools and
video availability. These limits are documented in the installation guide.
