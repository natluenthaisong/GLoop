import Foundation

enum HandoffError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

/// A portable practice request, never a command or a path to execute.
struct PracticeHandoff: Codable {
    var version: Int
    var url: String
    var title: String
    var a: Double
    var b: Double?
    var speed: Double
    var increment: Int

    var videoID: String { URLComponents(string: url)!.queryItems!.first(where: { $0.name == "v" })!.value! }
    var canonicalURL: String { "https://www.youtube.com/watch?v=\(videoID)" }

    static func decode(_ data: Data) throws -> PracticeHandoff {
        guard data.count <= 16_384 else { throw HandoffError.message("This practice file is too large.") }
        let handoff: PracticeHandoff
        do { handoff = try JSONDecoder().decode(Self.self, from: data) }
        catch { throw HandoffError.message("This is not a valid GLoop practice file.") }
        try handoff.validate()
        return handoff
    }
    func validate() throws {
        guard version == 1, let c = URLComponents(string: url), c.scheme == "https",
              ["youtube.com", "www.youtube.com"].contains(c.host ?? ""), c.path == "/watch",
              c.user == nil, c.password == nil, c.port == nil,
              let ids = c.queryItems?.filter({ $0.name == "v" }), ids.count == 1,
              let id = ids.first?.value, id.range(of: #"^[A-Za-z0-9_-]{11}$"#, options: .regularExpression) != nil,
              a.isFinite, a >= 0, a <= 86_400, speed.isFinite, (25...125).contains(speed),
              [0, 1, 5].contains(increment), title.count <= 500,
              !title.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw HandoffError.message("This practice file contains an unsupported link or setting.")
        }
        if let b { guard b.isFinite, b <= 86_400, b - a >= 0.25 else { throw HandoffError.message("The loop end must be at least 0.25 seconds after its start.") } }
    }
    func settings(duration: Double) throws -> ClipSettings {
        try validate()
        guard duration.isFinite, duration > a, b == nil || b! <= duration + 0.1 else {
            throw HandoffError.message("The saved loop is outside this video's duration. Choose the original full-length video.")
        }
        return ClipSettings(speed: speed / 100, a: a, b: b.map { min($0, duration) }, looping: true,
                            target: 0, autoIncrease: increment > 0, speedStep: increment == 1 ? 1 : 5)
    }
    /// A pasted link in any common YouTube form becomes a whole-clip practice request.
    /// Only the video ID and an optional start time are kept; nothing else from the link is used.
    static func fromLink(_ text: String) throws -> PracticeHandoff {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let invalid = HandoffError.message("Paste a YouTube video link, for example https://www.youtube.com/watch?v=… or https://youtu.be/….")
        guard !trimmed.isEmpty, trimmed.count <= 2048, !trimmed.contains(" "),
              let c = URLComponents(string: trimmed.range(of: "^https?://", options: [.regularExpression, .caseInsensitive]) != nil ? trimmed : "https://" + trimmed),
              ["https", "http"].contains(c.scheme?.lowercased() ?? ""), c.user == nil, c.password == nil, c.port == nil else { throw invalid }
        let host = (c.host ?? "").lowercased(), parts = c.path.split(separator: "/").map(String.init)
        var id: String?
        if ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com", "youtube-nocookie.com", "www.youtube-nocookie.com"].contains(host) {
            if c.path == "/watch" { id = c.queryItems?.first(where: { $0.name == "v" })?.value }
            else if parts.count == 2, ["shorts", "embed", "live", "v"].contains(parts[0]) { id = parts[1] }
        } else if host == "youtu.be", parts.count == 1 { id = parts[0] }
        guard let id, id.range(of: #"^[A-Za-z0-9_-]{11}$"#, options: .regularExpression) != nil else { throw invalid }
        let start = c.queryItems?.first(where: { ["t", "start"].contains($0.name) })?.value.map(offset) ?? 0
        return PracticeHandoff(version: 1, url: "https://www.youtube.com/watch?v=\(id)", title: "", a: start, b: nil, speed: 75, increment: 0)
    }
    /// YouTube time offsets: 90, 90s, 1m30s, 1h2m3s.
    static func offset(_ text: String) -> Double {
        if let seconds = Double(text), seconds.isFinite, seconds >= 0 { return min(86_400, seconds) }
        var total = 0.0, digits = ""
        for character in text {
            if character.isNumber { digits.append(character); continue }
            if let value = Double(digits) { total += value * (character == "h" ? 3600 : character == "m" ? 60 : character == "s" ? 1 : 0) }
            digits = ""
        }
        return min(86_400, total)
    }
    /// yt-dlp names files "Title [videoID].mp4"; the library shows just the title.
    static func title(forDownloaded url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        return name.replacingOccurrences(of: #"\s*\[[A-Za-z0-9_-]{11}\]$"#, with: "", options: .regularExpression)
    }
    static func read(_ url: URL) throws -> PracticeHandoff {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try decode(handle.read(upToCount: 16_385) ?? Data())
    }
    static func selfTest() throws {
        let base = Self(version: 1, url: "https://www.youtube.com/watch?v=abcdefghijk&list=ignored", title: "Practice phrase", a: 10, b: 12, speed: 75, increment: 1)
        let result = try decode(JSONEncoder().encode(base))
        precondition(result.canonicalURL == "https://www.youtube.com/watch?v=abcdefghijk")
        let prefs = try result.settings(duration: 20)
        precondition(prefs.a == 10 && prefs.b == 12 && prefs.speed == 0.75 && prefs.target == 0 && prefs.increasePoints == 1)
        precondition(prefs.nextLoopSpeed == 0.76)
        var cases = [Self]()
        for url in ["file:///etc/passwd", "https://youtube.com.evil.test/watch?v=abcdefghijk", "https://user@youtube.com/watch?v=abcdefghijk", "https://youtube.com/watch?v=abcdefghijk&v=ABCDEFGHIJK", "https://youtube.com/watch?v=--exec"] {
            var bad = base; bad.url = url; cases.append(bad)
        }
        var bad = base; bad.version = 2; cases.append(bad)
        bad = base; bad.speed = 0; cases.append(bad)
        bad = base; bad.increment = 20; cases.append(bad)
        bad = base; bad.b = 10.1; cases.append(bad)
        for item in cases { do { try item.validate(); preconditionFailure("Invalid handoff accepted") } catch is HandoffError {} }
        do { _ = try base.settings(duration: 5); preconditionFailure("Mismatched video accepted") } catch is HandoffError {}
        do { _ = try decode(Data(repeating: 32, count: 16_385)); preconditionFailure("Oversized file accepted") } catch is HandoffError {}
        for (link, start) in [("https://youtu.be/abcdefghijk?t=90", 90.0), ("https://www.youtube.com/watch?v=abcdefghijk&t=1m30s&list=x", 90), ("youtube.com/shorts/abcdefghijk", 0),
                              ("https://m.youtube.com/watch?v=abcdefghijk&start=5", 5), ("  HTTP://WWW.YOUTUBE.COM/watch?v=abcdefghijk  ", 0), ("https://www.youtube.com/embed/abcdefghijk?t=1h2m3s", 3723)] {
            let link = try fromLink(link)
            precondition(link.canonicalURL == "https://www.youtube.com/watch?v=abcdefghijk" && link.a == start && link.b == nil && link.speed == 75 && link.increment == 0, "Link parsing failed for \(link)")
            try link.validate()
        }
        for bad in ["", "not a link", "https://vimeo.com/123456", "https://youtube.com.evil.test/watch?v=abcdefghijk", "https://www.youtube.com/watch?v=--exec", "https://user@youtube.com/watch?v=abcdefghijk", "https://youtu.be/abcdefghijk/extra", "file:///etc/passwd"] {
            do { _ = try fromLink(bad); preconditionFailure("Bad link accepted: \(bad)") } catch is HandoffError {}
        }
        precondition(title(forDownloaded: URL(fileURLWithPath: "/tmp/My Song (Guitar Cover) [abcdefghijk].mp4")) == "My Song (Guitar Cover)")
        precondition(title(forDownloaded: URL(fileURLWithPath: "/tmp/plain.mp4")) == "plain")
        print("PASS: portable handoff, URL allowlist, canonical link, settings, invalid input, duration checks, pasted links and offsets")
    }
}
