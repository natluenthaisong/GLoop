# Third-party software

The MIT license covers GLoop's original source code and generated icon.

GLoop loads **libVLC** and VLC plugins from a separate installation of
[VLC 3](https://www.videolan.org/vlc/). VLC and libVLC are maintained by
VideoLAN and their contributors. The libVLC headers identify LGPL 2.1-or-later
licensing; VLC plugins and other components have their own upstream licenses.
No VLC code, headers, libraries or plugins are included in this repository.
See [VLC licensing](https://www.videolan.org/legal.html) and
[VLC source](https://code.videolan.org/videolan/vlc).

GLoop invokes a separately installed **FFmpeg** executable to decode audio.
FFmpeg is not bundled. Its license depends on the build configuration; see
[FFmpeg licensing](https://ffmpeg.org/legal.html).

AppKit, AVFoundation and Accelerate are Apple system frameworks supplied by
macOS. They are not part of the MIT-licensed source.

No songs, tablature, practice videos or other third-party media are included.
