import Foundation

final class VideoDownload {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    func cancel() {
        lock.lock(); cancelled = true; let p = process; lock.unlock()
        if let p, p.isRunning { p.interrupt() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { if let p, p.isRunning { p.terminate() } }
    }
    static func executable(_ name: String) -> String? {
        ["/opt/homebrew/bin/", "/usr/local/bin/"].map { $0 + name }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
    static func arguments(_ request: PracticeHandoff, folder: URL, ffmpeg: String, node: String?) -> [String] {
        var args = ["--ignore-config", "--no-plugin-dirs", "--no-remote-components", "--no-playlist",
                    "--no-write-info-json", "--no-write-thumbnail", "--no-write-subs", "--no-write-auto-subs",
                    "--match-filter", "!is_live & !is_upcoming", "--socket-timeout", "20", "--retries", "3",
                    "--no-simulate", "--quiet", "--progress", "--newline",
                    "--progress-template", "download:GLOOP_PROGRESS:%(progress._percent_str)s",
                    "--print", "after_move:GLOOP_FILE:%(filepath)j", "--ffmpeg-location", ffmpeg,
                    "--format", "bv*[vcodec^=avc1][height<=1080]+ba[acodec^=mp4a]/b[vcodec^=avc1][height<=1080]",
                    "--merge-output-format", "mp4", "--paths", folder.path,
                    "--output", "%(title).120B [%(id)s].%(ext)s"]
        if let node { args += ["--js-runtimes", "node:" + node] }
        return args + ["--", request.canonicalURL]
    }
    func run(_ request: PracticeHandoff, root: URL, progress: @escaping (String) -> Void) throws -> URL {
        try request.validate()
        guard let downloader = Self.executable("yt-dlp"), let ffmpeg = Self.executable("ffmpeg") else {
            throw HandoffError.message("Downloading needs yt-dlp and FFmpeg. Install them with Homebrew: brew install yt-dlp ffmpeg. Or choose a video you already downloaded.")
        }
        let folder = root.appendingPathComponent(request.videoID + "-" + UUID().uuidString.prefix(8), isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var succeeded = false
        defer { if !succeeded { try? FileManager.default.removeItem(at: folder) } }
        let p = Process(), output = Pipe()
        p.executableURL = URL(fileURLWithPath: downloader)
        p.arguments = Self.arguments(request, folder: folder, ffmpeg: ffmpeg, node: Self.executable("node"))
        p.standardInput = FileHandle.nullDevice; p.standardOutput = output; p.standardError = output
        lock.lock()
        if cancelled { lock.unlock(); throw HandoffError.message("Download cancelled.") }
        process = p
        do { try p.run(); lock.unlock() } catch { lock.unlock(); throw error }
        defer { lock.lock(); process = nil; lock.unlock() }
        var pending = Data(), tail = "", file: String?
        func line(_ data: Data) {
            let text = String(decoding: data, as: UTF8.self)
            if text.hasPrefix("GLOOP_PROGRESS:") {
                let percent = text.dropFirst("GLOOP_PROGRESS:".count).trimmingCharacters(in: .whitespacesAndNewlines)
                progress("Downloading \(percent)")
            } else if text.hasPrefix("GLOOP_FILE:") {
                file = try? JSONDecoder().decode(String.self, from: Data(text.dropFirst("GLOOP_FILE:".count).utf8))
            } else { tail = String((tail + text + "\n").suffix(3000)) }
        }
        while true {
            let bytes = output.fileHandleForReading.availableData
            if bytes.isEmpty { break }
            pending.append(bytes)
            while let newline = pending.firstIndex(of: 10) { line(pending.prefix(upTo: newline)); pending.removeSubrange(...newline) }
            if pending.count > 65_536 { pending.removeAll() }
        }
        if !pending.isEmpty { line(pending) }
        p.waitUntilExit()
        lock.lock(); let wasCancelled = cancelled; lock.unlock()
        if wasCancelled { throw HandoffError.message("Download cancelled.") }
        guard p.terminationStatus == 0, let file else {
            let detail = tail.trimmingCharacters(in: .whitespacesAndNewlines)
            throw HandoffError.message("Could not download this video. Update yt-dlp and try again, or choose an existing video.\n\n" + detail)
        }
        let media = URL(fileURLWithPath: file).resolvingSymlinksInPath()
        let base = folder.resolvingSymlinksInPath().path + "/"
        guard media.path.hasPrefix(base), ["mp4", "mkv", "webm", "mov"].contains(media.pathExtension.lowercased()),
              (try? media.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
            throw HandoffError.message("The download did not produce a video file.")
        }
        // Keep a portable copy of the phrase beside its media; never part of a release.
        try JSONEncoder().encode(request).write(to: folder.appendingPathComponent("Practice.gloop"), options: .atomic)
        succeeded = true
        return media
    }
    static func duration(_ url: URL) throws -> Double {
        try NativeAudio.duration(url)
    }
    func convert(_ source: URL, root: URL) throws -> URL {
        guard let ffmpeg = Self.executable("ffmpeg") else { throw HandoffError.message("Converting this format needs FFmpeg. Install it with brew install ffmpeg, or open a compatible MP4/MOV directly.") }
        let folder = root.appendingPathComponent("Converted-" + UUID().uuidString.prefix(8), isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent(source.deletingPathExtension().lastPathComponent + ".mp4")
        var succeeded = false
        defer { if !succeeded { try? FileManager.default.removeItem(at: folder) } }
        let p = Process(); p.executableURL = URL(fileURLWithPath: ffmpeg)
        p.arguments = ["-nostdin", "-v", "error", "-i", source.path, "-map", "0:v:0", "-map", "0:a:0?", "-c:v", "libx264", "-preset", "fast", "-crf", "20", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", "-n", target.path]
        p.standardInput = FileHandle.nullDevice; p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        lock.lock()
        if cancelled { lock.unlock(); throw HandoffError.message("Conversion cancelled.") }
        process = p
        do { try p.run(); lock.unlock() } catch { lock.unlock(); throw error }
        p.waitUntilExit()
        lock.lock(); process = nil; let wasCancelled = cancelled; lock.unlock()
        if wasCancelled { throw HandoffError.message("Conversion cancelled.") }
        guard p.terminationStatus == 0 else { throw HandoffError.message("Conversion failed. Check the original file and available disk space.") }
        _ = try NativeAudio.duration(target)
        succeeded = true
        return target
    }
}
