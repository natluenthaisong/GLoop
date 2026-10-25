import Foundation

func practiceStatsTests() throws {
    func check(_ value: @autoclosure () -> Bool, _ name: String) throws {
        if !value() { throw NSError(domain: "Practice stats test",code: 1,userInfo: [NSLocalizedDescriptionKey:name]) }
    }
    let clip = Clip(title: "Phrase",song: "Test",path: "/test/phrase.mp4",duration: 10)
    let p = PracticeStats(); p.select(clip); p.prepare(a: 0,b: 2,position: 0,speed: 0.5)
    let date = Date(timeIntervalSince1970: 1700000000)
    for i in 0...4 { p.sample(wall: Double(i),media: Double(i)*0.5,running: true,speed: 0.5,date: date.addingTimeInterval(Double(i))) }
    p.boundary(speed: 0.5,date: date.addingTimeInterval(4))
    try check(abs(p.currentSession!.seconds-4) < 0.001,"Slower playback counts real elapsed time")
    try check(p.currentSession!.loops.count == 1,"A full loop is counted")
    p.speedChanged(0.55,automatic: true)
    try check(p.latestLoop?.lowSpeed == 0.5,"Auto increase keeps the completed loop's old speed")
    try check(p.markClean(true) && !p.markClean(true),"Clean mark is idempotent")
    try check(p.latestLoop?.clean == true && p.markClean(false),"Clean can be undone")
    try check(p.markClean(true),"Mark a loop for later undo")
    // No time for pause, stalled media, a seek jump, or system sleep.
    let before = p.currentSession!.seconds
    p.sample(wall: 5,media: 2,running: false,speed: 0.55)
    p.sample(wall: 6,media: 2,running: true,speed: 0.55)
    p.sample(wall: 7,media: 2,running: true,speed: 0.55)
    p.sample(wall: 8,media: 9,running: true,speed: 0.55)
    p.sample(wall: 100,media: 50,running: true,speed: 0.55)
    try check(p.currentSession!.seconds == before,"Idle, stalls, seeks and sleep add no time")
    p.boundary(speed: 0.55)
    try check(p.currentSession!.loops.count == 1,"Skipped media adds no loops")
    // A partial first pass is excluded, the next complete pass is counted.
    p.prepare(a: 0,b: 2,position: 1,speed: 1)
    p.sample(wall: 101,media: 0,running: true,speed: 1)
    p.sample(wall: 102,media: 1,running: true,speed: 1); p.boundary(speed: 1)
    p.sample(wall: 103,media: 2,running: true,speed: 1)
    p.sample(wall: 104,media: 3,running: true,speed: 1); p.boundary(speed: 1)
    try check(p.data.sessions.flatMap(\.loops).count == 2,"Partial seek pass excluded; next full loop included")
    try check(p.canUndoClean && p.undoCleanMark() && p.data.sessions.flatMap(\.loops).filter(\.clean).isEmpty,"Undo still works after another loop finishes")
    // Mid-loop manual speed changes record a range, not a false clean speed record.
    p.prepare(a: 0,b: 2,position: 0,speed: 0.5)
    p.sample(wall: 105,media: 0,running: true,speed: 0.5)
    p.sample(wall: 106,media: 0.5,running: true,speed: 0.5)
    p.sample(wall: 107,media: 1,running: true,speed: 0.5)
    p.speedChanged(1,automatic: false)
    p.sample(wall: 108,media: 2,running: true,speed: 1); p.boundary(speed: 1)
    try check(p.latestLoop?.lowSpeed == 0.5 && p.latestLoop?.highSpeed == 1,"Mixed speed loop retains speed range")
    try check(p.currentSession!.speeds.count >= 3,"Speed history records transitions")
    p.select(Clip(title: "Other",song: "Test",path: "/test/other.mp4",duration: 10))
    try check(!p.markClean(true),"Switching clips cannot mark an old loop")
    let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: temp,withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temp) }
    let url = temp.appendingPathComponent("PracticeStats.json")
    let store = PracticeStatsStore(url: url)
    store.save(p.data,wait: true); store.save(p.data,wait: true)
    let read = try PracticeStatsStore.read(url)
    try check(read.sessions.flatMap(\.loops).count == 3,"Persistence round trip")
    try Data("broken".utf8).write(to: url)
    let recovered = PracticeStatsStore(url: url)
    try check(recovered.load().sessions.count == read.sessions.count && recovered.notice != nil,"Corrupt history recovers readable backup")
    let files = try FileManager.default.contentsOfDirectory(atPath: temp.path)
    try check(files.contains { $0.hasPrefix("PracticeStats-unreadable-") },"Corrupt original preserved")
    var future = p.data; future.version = 2
    try JSONEncoder().encode(future).write(to: url)
    let blocked = PracticeStatsStore(url: url); _ = blocked.load(); blocked.save(p.data,wait: true)
    let preserved = try JSONDecoder().decode(PracticeStatsData.self,from: Data(contentsOf: url))
    try check(blocked.blocked && preserved.version == 2,"Unknown schema never overwritten")
    let isolated = PracticeStatsStore(url: nil); isolated.save(p.data,wait: true)
    try check(isolated.load().sessions.isEmpty,"Test mode has no disk state")
    print("Practice stats tests passed: timing, pauses, stalls, seeks, sleep, partial loops, speed history, clean/undo, clip isolation, persistence and recovery.")
}
