# Third-party software

The MIT license covers GLoop's original source code and generated icon.

GLoop 3 uses Apple system frameworks for playback, audio decoding and tempo
analysis. It does not bundle or link VLC, FFmpeg or yt-dlp.

For optional format conversion and YouTube downloads, GLoop invokes a separately
installed **FFmpeg** executable. Its license depends on the build configuration; see
[FFmpeg licensing](https://ffmpeg.org/legal.html).

For optional YouTube downloads, GLoop invokes a separately installed
[yt-dlp](https://github.com/yt-dlp/yt-dlp). It is not bundled. See its
[upstream license](https://github.com/yt-dlp/yt-dlp/blob/master/LICENSE) and
third-party notices for the distribution you install.

AppKit, AVFoundation and Accelerate are Apple system frameworks supplied by
macOS. They are not part of the MIT-licensed source.

No songs, tablature, practice videos or other third-party media are included.

Optional AI Trim launches a separately installed Agent Client Protocol agent.
No agent or ACP SDK is bundled; GLoop implements the ACP v1 stdio protocol.
An agent and its model provider have their own licenses, terms and billing.
