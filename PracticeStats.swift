import Foundation

struct PracticeSpeedSpan: Codable {
    var date: Date
    var a: Double
    var b: Double
    var speed: Double
    var seconds: Double
}
struct PracticeLoop: Codable {
    var id = UUID()
    var date: Date
    var a: Double
    var b: Double
    var lowSpeed: Double
    var highSpeed: Double
    var clean = false
}
struct PracticeSession: Codable {
    var id = UUID()
    var clip: Clip
    var started: Date
    var ended: Date
    var speeds: [PracticeSpeedSpan] = []
    var loops: [PracticeLoop] = []
    var seconds: Double { speeds.reduce(0) { $0 + $1.seconds } }
}
struct PracticeStatsData: Codable {
    var version = 1
    var sessions: [PracticeSession] = []
}

/// All mutations occur on the main thread. The playback clock, not a wall timer,
/// establishes activity. Pauses and seeks reset the clock baseline.
final class PracticeStats {
    var data = PracticeStatsData()
    var clip: Clip?
    var sessionID: UUID?
    var latestLoopID: UUID?
    private var cleanUndo: (session: UUID, loop: UUID)?
    var canUndoClean: Bool { cleanUndo != nil }
    var changed = false
    var a = 0.0, b = 0.0
    private var previous: (wall: Double, media: Double, running: Bool)?
    private var distance = 0.0
    private var eligible = false
    private var low = 1.0, high = 1.0
    private var lastActivity: Date?

    func select(_ value: Clip?) {
        clip = value; sessionID = nil; latestLoopID = nil; cleanUndo = nil; previous = nil
        distance = 0; eligible = false; lastActivity = nil
    }
    func prepare(a: Double, b: Double, position: Double, speed: Double) {
        self.a = a; self.b = b; distance = 0; previous = nil
        eligible = abs(position-a) < 0.002; low = speed; high = speed
    }
    func resetClock() { previous = nil }
    func speedChanged(_ speed: Double, automatic: Bool) {
        if automatic || distance < 0.002 { low = speed; high = speed }
        else { low = min(low,speed); high = max(high,speed) }
    }
    private func session(at date: Date) -> Int? {
        guard let clip else { return nil }
        if let id = sessionID, let index = data.sessions.lastIndex(where: { $0.id == id }),
           lastActivity.map({ date.timeIntervalSince($0) < 300 }) ?? true { return index }
        let value = PracticeSession(clip: clip, started: date, ended: date)
        data.sessions.append(value); sessionID = value.id; latestLoopID = nil
        return data.sessions.count-1
    }
    func sample(wall: Double, media: Double, running: Bool, speed: Double, date: Date = Date()) {
        guard wall.isFinite, media.isFinite, speed.isFinite, speed > 0 else { previous = nil; return }
        defer { previous = (wall,media,running) }
        guard let prev = previous, prev.running, running else { return }
        let dt = wall-prev.wall, delta = media-prev.media
        guard dt > 0 else { return }
        // Long scheduling gaps (including sleep) and clock jumps cannot establish practice.
        guard dt <= 2, delta >= 0, delta <= dt*speed+0.2 else { eligible = false; distance = 0; return }
        guard delta > 0 else { return }
        let seconds = min(delta/speed,dt+0.05)
        guard let index = session(at: date) else { return }
        let n = data.sessions[index].speeds.count
        if n > 0, let span = data.sessions[index].speeds.last,
           abs(span.speed-speed) < 0.0001, span.a == a, span.b == b, Calendar.current.isDate(span.date,inSameDayAs: date) {
            data.sessions[index].speeds[n-1].seconds += seconds
        } else {
            data.sessions[index].speeds.append(PracticeSpeedSpan(date: date,a: a,b: b,speed: speed,seconds: seconds))
        }
        data.sessions[index].ended = date; lastActivity = date
        distance += delta; changed = true
    }
    func boundary(speed: Double, date: Date = Date()) {
        let length = b-a
        if eligible, length > 0, distance >= length-min(0.03,length*0.02), let index = session(at: date) {
            let loop = PracticeLoop(date: date,a: a,b: b,lowSpeed: min(low,speed),highSpeed: max(high,speed))
            data.sessions[index].loops.append(loop); data.sessions[index].ended = date
            latestLoopID = loop.id; lastActivity = date; changed = true
        }
        distance = max(0,distance-length); eligible = true; low = speed; high = speed
    }
    var currentSession: PracticeSession? { data.sessions.last { $0.id == sessionID } }
    var latestLoop: PracticeLoop? { currentSession?.loops.last { $0.id == latestLoopID } }
    @discardableResult func markClean(_ clean: Bool) -> Bool {
        guard let s = data.sessions.lastIndex(where: { $0.id == sessionID }),
              let l = data.sessions[s].loops.lastIndex(where: { $0.id == latestLoopID }),
              data.sessions[s].loops[l].clean != clean else { return false }
        data.sessions[s].loops[l].clean = clean
        cleanUndo = clean ? (data.sessions[s].id,data.sessions[s].loops[l].id) : nil
        changed = true; return true
    }
    @discardableResult func undoCleanMark() -> Bool {
        guard let undo = cleanUndo,
              let s = data.sessions.lastIndex(where: { $0.id == undo.session }),
              let l = data.sessions[s].loops.lastIndex(where: { $0.id == undo.loop }) else { return false }
        data.sessions[s].loops[l].clean = false; cleanUndo = nil; changed = true; return true
    }
}

/// Atomic local snapshots, with a last-readable backup. A future schema or a file
/// that cannot be preserved is never overwritten by this version.
final class PracticeStatsStore {
    let url: URL?
    private let queue = DispatchQueue(label: "local.gloop.stats", qos: .utility)
    var blocked = false
    var notice: String?
    var onError: ((String) -> Void)?
    init(url: URL?) { self.url = url }
    static func read(_ url: URL) throws -> PracticeStatsData {
        let value = try JSONDecoder().decode(PracticeStatsData.self,from: Data(contentsOf: url))
        guard value.version == 1 else { throw NSError(domain: "GLoop Stats",code: 2,userInfo: [NSLocalizedDescriptionKey:"This practice history needs a newer GLoop version."]) }
        guard value.sessions.allSatisfy({ s in
            s.speeds.allSatisfy { $0.seconds.isFinite && $0.seconds >= 0 && $0.speed.isFinite && $0.speed > 0 && $0.a >= 0 && $0.b > $0.a } &&
            s.loops.allSatisfy { $0.a >= 0 && $0.b > $0.a && $0.lowSpeed > 0 && $0.highSpeed >= $0.lowSpeed }
        }) else { throw NSError(domain: "GLoop Stats",code: 1,userInfo: [NSLocalizedDescriptionKey:"Practice history contains invalid values."]) }
        return value
    }
    func load() -> PracticeStatsData {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return PracticeStatsData() }
        do { return try Self.read(url) }
        catch {
            if (error as NSError).domain == "GLoop Stats", (error as NSError).code == 2 {
                blocked = true; notice = error.localizedDescription; return PracticeStatsData()
            }
            do { try FileManager.default.copyItem(at: url,to: url.deletingLastPathComponent().appendingPathComponent("PracticeStats-unreadable-\(UUID()).json")) }
            catch { blocked = true; notice = "Practice history could not be read or backed up. Saving stats is disabled to protect it."; return PracticeStatsData() }
            if let backup = try? Self.read(url.appendingPathExtension("backup")) {
                notice = "Practice history restored from backup. The unreadable file was preserved."; return backup
            }
            notice = "Practice history could not be read. The original was preserved; new history starts here."
            return PracticeStatsData()
        }
    }
    func save(_ value: PracticeStatsData, wait: Bool = false) {
        guard let url, !blocked else { return }
        let operation = { [self] in
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),withIntermediateDirectories: true)
                if (try? Self.read(url)) != nil {
                    try Data(contentsOf: url).write(to: url.appendingPathExtension("backup"),options: .atomic)
                }
                try JSONEncoder().encode(value).write(to: url,options: .atomic)
            } catch {
                let message = "Practice stats could not be saved: " + error.localizedDescription
                DispatchQueue.main.async { [weak self] in self?.onError?(message) }
            }
        }
        if wait { queue.sync(execute: operation) } else { queue.async(execute: operation) }
    }
}
