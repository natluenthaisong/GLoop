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
    var nextLoopSpeed: Double { autoIncrease == true && speed < 1 ? min(1, (speed * 100 + Double(increasePoints)).rounded() / 100) : speed }
}
struct SavedState: Codable {
    var settings: [String: ClipSettings] = [:]
    var imports: [Clip] = []
    var lastPath: String? = nil
    var volume: Int32 = 55
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
    precondition(legacy.speed == 0.65 && legacy.autoIncrease != true)
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
    print("PASS: 1% increments, legacy 5% default,  speed progression, cap, disabled mode, legacy settings,  repeat count, unlimited mode, single play, time parsing, and settings persistence")
}
