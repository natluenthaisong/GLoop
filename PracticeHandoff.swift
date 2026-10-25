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
        print("PASS: portable handoff, URL allowlist, canonical link, settings, invalid input and duration checks")
    }
}
