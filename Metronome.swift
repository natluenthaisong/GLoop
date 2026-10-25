import Foundation
import AVFoundation

struct BeatEvent {
    let index: Int
    let delay: Double
}
struct BeatClock {
    var lastScheduled: Int?
    mutating func reset() { lastScheduled = nil }
    // Grid is expressed in original-media seconds, so tempo remains tied to the video.
    mutating func events(position: Double, bpm: Double, rate: Double, anchor: Double) -> [BeatEvent] {
        guard bpm.isFinite, rate.isFinite, position.isFinite, anchor.isFinite, bpm > 0, rate > 0 else { return [] }
        let period = 60/bpm
        let first = max(Int(floor((position-anchor)/period)), (lastScheduled ?? Int.min)+1)
        let last = Int(floor((position+0.12*rate-anchor)/period))
        guard last >= first else { return [] }
        var result: [BeatEvent] = []
        for beat in first...last {
            let delay = (anchor+Double(beat)*period-position)/rate
            if delay >= -0.035 && delay <= 0.12 {
                result.append(BeatEvent(index: beat,delay: max(0.01,delay))); lastScheduled = beat
            }
        }
        return result
    }
}
final class PracticeMetronome {
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    let format = AVAudioFormat(standardFormatWithSampleRate: 48000,channels: 1)!
    var clock = BeatClock()
    var lastBPM: Double?
    var lastRate: Double?
    var lastAnchor: Double?
    var scheduledCount = 0
    var lastInterval = 0.0
    var failure: String?
    var isPlaying: Bool { player.isPlaying }
    lazy var click = Self.makeClick(format: format)
    init() {
        engine.attach(player); engine.connect(player,to: engine.mainMixerNode,format: format)
    }
    static func makeClick(format: AVAudioFormat) -> AVAudioPCMBuffer {
        let count = AVAudioFrameCount(format.sampleRate*0.028)
        let buffer = AVAudioPCMBuffer(pcmFormat: format,frameCapacity: count)!
        buffer.frameLength = count
        for i in 0..<Int(count) {
            let t = Double(i)/format.sampleRate
            let attack = min(1,t/0.001)
            buffer.floatChannelData![0][i] = Float(0.65*attack*exp(-t/0.005)*sin(2*Double.pi*1600*t))
        }
        return buffer
    }
    func reset() { player.stop(); clock.reset(); lastBPM = nil; lastRate = nil; lastAnchor = nil }
    func stop() { if player.isPlaying || clock.lastScheduled != nil { reset() } }
    func shutdown() { reset(); engine.stop() }
    func sync(position: Double, bpm: Double?, rate: Double, anchor: Double, active: Bool, volume: Double) {
        guard active, let bpm, bpm.isFinite, (20...400).contains(bpm), failure == nil else { stop(); return }
        if lastBPM != bpm || lastRate != rate || lastAnchor != anchor { reset(); lastBPM = bpm; lastRate = rate; lastAnchor = anchor }
        player.volume = Float(min(1,max(0,volume)))
        do { if !engine.isRunning { try engine.start() }; if !player.isPlaying { player.play() } }
        catch { failure = "Metronome audio unavailable: \(error.localizedDescription)"; stop(); return }
        let host = mach_absolute_time()
        for beat in clock.events(position: position,bpm: bpm,rate: rate,anchor: anchor) {
            player.scheduleBuffer(click,at: AVAudioTime(hostTime: host+AVAudioTime.hostTime(forSeconds: beat.delay)),options: [])
            scheduledCount += 1; lastInterval = 60/(bpm*rate)
        }
    }
    static func selfTest() throws {
        // Timing at normal/slowed speeds; every beat is emitted once, without drift.
        for rate in [0.75,0.76,1.0] {
            var clock = BeatClock(); var times: [Double] = []
            for tick in 0..<500 {
                let time = Double(tick)*0.01
                for event in clock.events(position: time*rate,bpm: 120,rate: rate,anchor: 0) {
                    if event.index > 0 { times.append(time+event.delay) }
                }
            }
            precondition(times.count >= 6)
            for i in 1..<times.count { precondition(abs(times[i]-times[i-1]-0.5/rate) < 0.011) }
        }
        var clock = BeatClock()
        precondition(clock.events(position: 3,bpm: 120,rate: 0.75,anchor: 3).count == 1)
        precondition(clock.events(position: 3,bpm: 120,rate: 0.75,anchor: 3).isEmpty)
        clock.reset(); precondition(clock.events(position: 3,bpm: 120,rate: 0.76,anchor: 3).count == 1)
        // Render the real audio graph offline; no sound or microphone access is needed.
        let metronome = PracticeMetronome()
        try metronome.engine.enableManualRenderingMode(.offline,format: metronome.format,maximumFrameCount: 1024)
        metronome.player.volume = 0.4
        for beat in 0..<4 {
            metronome.player.scheduleBuffer(metronome.click,at: AVAudioTime(sampleTime: Int64(beat*24000),atRate: 48000),options: [])
        }
        try metronome.engine.start(); metronome.player.play()
        let output = AVAudioPCMBuffer(pcmFormat: metronome.format,frameCapacity: 1024)!
        var samples: [Float] = []
        while samples.count < 96000 {
            let result = try metronome.engine.renderOffline(min(1024,AVAudioFrameCount(96000-samples.count)),to: output)
            guard result == .success else { throw BPMError.message("Offline metronome render failed") }
            samples += Array(UnsafeBufferPointer(start: output.floatChannelData![0],count: Int(output.frameLength)))
        }
        let starts = samples.indices.filter { abs(samples[$0]) > 0.002 && ($0 == 0 || abs(samples[$0-1]) <= 0.002) }
        var groups: [Int] = []
        for index in starts { if groups.last.map({ index-$0 > 2400 }) ?? true { groups.append(index) } }
        precondition(groups.count == 4,"Expected 4 audible clicks, got \(groups.count)")
        for i in 1..<groups.count { precondition(abs(groups[i]-groups[i-1]-24000) < 3) }
        metronome.stop(); precondition(!metronome.isPlaying); metronome.shutdown()
        print("PASS metronome: 75%/76%/100% timing, loop reset, duplicate prevention, four rendered clicks, and stop")
    }
}
