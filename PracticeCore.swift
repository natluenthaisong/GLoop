import Foundation

struct Clip: Codable, Equatable {
    var title: String
    var song: String
    var path: String
    var duration: Double
}
struct ClipSettings: Codable {
    var speed: Double = 0.75
    var a: Double = 0
    var b: Double? = nil
    var looping: Bool = true
    var target: Int = 30
    var autoIncrease: Bool? = nil
    var speedStep: Int? = nil
    var metronomeEnabled: Bool? = nil
    var clickVolume: Double? = nil
    var beatAnchor: Double? = nil
    var increasePoints: Int { speedStep == 1 ? 1 : 5 }
    var bpm: Double? = nil
    var bpmNote: String? = nil
    var pitchSemitones: Int? = nil
    var pitchShift: Int { min(12,max(-12,pitchSemitones ?? 0)) }
    var nextLoopSpeed: Double { autoIncrease == true && speed < 1 ? min(1, (speed * 100 + Double(increasePoints)).rounded() / 100) : speed }
}
struct SavedState: Codable {
    var settings: [String: ClipSettings] = [:]
    var imports: [Clip] = []
    var lastPath: String? = nil
    var volume: Int32 = 55
    var hiddenPaths: [String]? = nil
}
extension ClipSettings {
    func normalized(duration: Double = 0) -> ClipSettings {
        var copy = self
        copy.pitchSemitones = pitchSemitones.map { min(12,max(-12,$0)) }
        copy.speed = speed.isFinite ? min(1.25, max(0.25, speed)) : 0.75
        copy.a = a.isFinite ? min(86400, max(0, a)) : 0
        if let b, !b.isFinite || b <= copy.a + 0.15 || b > 86400 { copy.b = nil }
        if duration > 0 {
            if copy.a >= max(0, duration - 0.15) { copy.a = 0 }
            if let b = copy.b { copy.b = min(duration, b); if copy.b! <= copy.a + 0.15 { copy.b = nil } }
        }
        copy.target = [0,5,10,30,50].contains(target) ? target : 30
        copy.speedStep = speedStep == 1 ? 1 : 5
        if let bpm, !bpm.isFinite || !(20...400).contains(bpm) { copy.bpm = nil; copy.metronomeEnabled = false }
        if let clickVolume { copy.clickVolume = clickVolume.isFinite ? min(1, max(0, clickVolume)) : 0.3 }
        if let beatAnchor, !beatAnchor.isFinite || beatAnchor < 0 || beatAnchor > 86400 { copy.beatAnchor = nil }
        return copy
    }
}
enum StateStore {
    static func load(_ url: URL) throws -> SavedState {
        var state = try JSONDecoder().decode(SavedState.self, from: Data(contentsOf: url))
        state.volume = min(100, max(0, state.volume))
        state.settings = state.settings.mapValues { $0.normalized() }
        var paths = Set<String>()
        state.imports = state.imports.filter { $0.path.hasPrefix("/") && paths.insert($0.path).inserted }.map {
            var clip = $0; if !clip.duration.isFinite || clip.duration < 0 { clip.duration = 0 }; return clip
        }
        return state
    }
    static func save(_ state: SavedState, to url: URL) throws {
        let data = try JSONEncoder().encode(state)
        // Preserve a readable prior version before replacing it atomically.
        if let previous = try? Data(contentsOf: url), (try? JSONDecoder().decode(SavedState.self, from: previous)) != nil {
            try previous.write(to: url.deletingPathExtension().appendingPathExtension("backup.json"), options: .atomic)
        }
        try data.write(to: url, options: .atomic)
    }
    static func selfTest() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("GLoop-state-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("State.json")
        var state = SavedState(); state.settings["clip"] = ClipSettings(speed: 500, a: 999, b: 1000, target: -5, bpm: 1)
        try save(state, to: url)
        let restored = try load(url).settings["clip"]!.normalized(duration: 10)
        precondition(restored.speed == 1.25 && restored.a == 0 && restored.b == 10 && restored.target == 30 && restored.bpm == nil)
        state.volume = 25; try save(state, to: url)
        let previous = try load(folder.appendingPathComponent("State.backup.json"))
        precondition(previous.volume == 55)
        try Data("broken".utf8).write(to: url)
        do { _ = try load(url); preconditionFailure("Corrupt settings accepted") } catch is DecodingError {}
        print("PASS: setting normalization, persistence, readable backup and corruption detection")
    }
}
struct LoopCounter {
    var completed = 0
    var finished = false
    mutating func reset() { completed = 0; finished = false }
    mutating func boundary(looping: Bool, target: Int) -> Bool {
        guard !finished else { return false }
        completed += 1
        if !looping || (target > 0 && completed >= target) { finished = true; return false }
        return true
    }
}
func stamp(_ seconds: Double, precise: Bool = false) -> String {
    let t = max(0, seconds.isFinite ? seconds : 0)
    return precise ? String(format: "%d:%06.3f", Int(t)/60, t.truncatingRemainder(dividingBy: 60)) : String(format: "%d:%02d", Int(t)/60, Int(t)%60)
}
func parseStamp(_ value: String) -> Double? {
    let bits = value.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":", omittingEmptySubsequences: false)
    guard (1...3).contains(bits.count) else { return nil }
    var total = 0.0
    for (i, bit) in bits.enumerated() {
        guard let n = Double(bit), n.isFinite, n >= 0, (i == 0 || n < 60) else { return nil }
        total = total * 60 + n
    }
    return total
}
func runCoreTests() {
    var c = LoopCounter()
    for i in 1...30 { precondition(c.boundary(looping: true, target: 30) == (i < 30)) }
    precondition(c.completed == 30 && c.finished)
    precondition(!c.boundary(looping: true, target: 30) && c.completed == 30)
    c.reset()
    for _ in 0..<100 { precondition(c.boundary(looping: true, target: 0)) }
    precondition(!c.finished)
    c.reset(); precondition(!c.boundary(looping: false, target: 30))
    precondition(parseStamp("1:02.500") == 62.5)
    precondition(parseStamp("1:99") == nil && parseStamp("nan") == nil && parseStamp("-1") == nil)
    let state = SavedState(settings: ["clip": ClipSettings(speed: 0.65, a: 1.5, b: 5.5, looping: true, target: 10)])
    let copy = try! JSONDecoder().decode(SavedState.self, from: JSONEncoder().encode(state))
    precondition(copy.settings["clip"]?.a == 1.5 && copy.settings["clip"]?.target == 10)
    let legacy = try! JSONDecoder().decode(ClipSettings.self, from: Data(#"{"speed":0.65,"a":1.5,"b":5.5,"looping":true,"target":10}"#.utf8))
    precondition(legacy.speed == 0.65 && legacy.autoIncrease != true && legacy.pitchShift == 0)
    for shift in [-12,-1,0,1,12] {
        var pitched = legacy; pitched.pitchSemitones = shift
        let restored = try! JSONDecoder().decode(ClipSettings.self,from: JSONEncoder().encode(pitched))
        precondition(restored.pitchShift == shift && restored.speed == legacy.speed && restored.a == legacy.a && restored.b == legacy.b)
    }
    var bounded = legacy; bounded.pitchSemitones = 999
    precondition(bounded.normalized().pitchShift == 12)
    bounded.pitchSemitones = -999; precondition(bounded.normalized().pitchShift == -12)
    var ramp = ClipSettings(speed: 0.90, autoIncrease: true)
    precondition(ramp.nextLoopSpeed == 0.95)
    ramp.speed = ramp.nextLoopSpeed; precondition(ramp.nextLoopSpeed == 1)
    ramp.speed = 1; precondition(ramp.nextLoopSpeed == 1)
    ramp.speed = 1.1; precondition(ramp.nextLoopSpeed == 1.1)
    ramp.autoIncrease = false; ramp.speed = 0.75; precondition(ramp.nextLoopSpeed == 0.75)
    ramp.autoIncrease = true; ramp.speedStep = 1; ramp.speed = 0.75
    for expected in [0.76,0.77,0.78,0.79,0.80] { ramp.speed = ramp.nextLoopSpeed; precondition(abs(ramp.speed-expected)<0.0001) }
    ramp.speed = 0.99; precondition(ramp.nextLoopSpeed == 1)
    precondition(legacy.increasePoints == 5 && legacy.metronomeEnabled != true)
    print("PASS: 1% increments, legacy 5% default,  speed progression, cap, disabled mode, legacy settings, pitch persistence/bounds, repeat count, unlimited mode, single play, time parsing, and settings persistence")
}
