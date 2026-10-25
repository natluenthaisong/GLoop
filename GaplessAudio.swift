import Foundation
import AVFoundation

/// PCM is queued before playback. A repeat never stops or seeks the audio node.
final class GaplessAudio {
    let engine = AVAudioEngine()
    let node = AVAudioPlayerNode()
    let stretch = AVAudioUnitTimePitch()
    let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
    var buffer: AVAudioPCMBuffer?
    private var held: [AVAudioPCMBuffer] = []
    private var start = 0.0, end = 0.0, firstStart = 0.0, firstLength = 0.0
    private var limit = 0
    private var cachedTime = 0.0
    var configured = false
    var ready: Bool { buffer != nil }
    var isPlaying: Bool { node.isPlaying }
    var duration: Double { Double(buffer?.frameLength ?? 0)/format.sampleRate }
    var rate: Double { get { Double(stretch.rate) } set { stretch.rate = Float(newValue) } }
    var volume: Float { get { node.volume } set { node.volume = newValue } }
    init() {
        engine.attach(node); engine.attach(stretch)
        engine.connect(node,to: stretch,format: format)
        engine.connect(stretch,to: engine.mainMixerNode,format: format)
        stretch.overlap = 8
    }
    func clear() { node.stop(); buffer = nil; held = []; configured = false; cachedTime = 0 }
    func shutdown() { clear(); engine.stop() }
    var consumed: Double {
        if let t = node.lastRenderTime, let p = node.playerTime(forNodeTime: t) {
            cachedTime = max(cachedTime,Double(p.sampleTime)/p.sampleRate)
        }
        return cachedTime
    }
    var completed: Int {
        let t = consumed
        guard configured, t >= firstLength, end > start else { return 0 }
        let n = 1 + Int((t-firstLength)/(end-start))
        return limit > 0 ? min(limit,n) : n
    }
    var position: Double {
        guard configured else { return firstStart }
        let t = consumed
        if limit > 0 && t >= firstLength+Double(limit-1)*(end-start) { return end }
        if t < firstLength { return firstStart+t }
        return start+(t-firstLength).truncatingRemainder(dividingBy: end-start)
    }
    func configure(a: Double,b: Double,position: Double,plays: Int) {
        node.stop(); stretch.auAudioUnit.reset(); cachedTime = 0; held = []; configured = false
        guard let buffer else { return }
        let lo = max(0,min(Int(a*48000),Int(buffer.frameLength)-1))
        let hi = min(Int(buffer.frameLength),max(lo+1,Int((b*48000).rounded())))
        let pos = min(hi-1,max(lo,Int(position*48000)))
        start = Double(lo)/48000; end = Double(hi)/48000; firstStart = Double(pos)/48000
        firstLength = Double(hi-pos)/48000; limit = plays
        let phrase = Self.slice(buffer,from: lo,to: hi,soften: true)
        let first = pos == lo ? phrase : Self.slice(buffer,from: pos,to: hi,soften: true)
        held = [first,phrase]
        node.scheduleBuffer(first,at: nil,options: [])
        if plays == 0 { node.scheduleBuffer(phrase,at: nil,options: .loops) }
        else if plays > 1 { for _ in 1..<plays { node.scheduleBuffer(phrase,at: nil,options: []) } }
        configured = true
    }
    func play() throws { if !engine.isRunning { try engine.start() }; node.play() }
    func pause() { _ = consumed; node.pause() }
    static func slice(_ source: AVAudioPCMBuffer,from: Int,to: Int,soften: Bool) -> AVAudioPCMBuffer {
        let n = to-from
        let output = AVAudioPCMBuffer(pcmFormat: source.format,frameCapacity: AVAudioFrameCount(n))!
        output.frameLength = AVAudioFrameCount(n)
        for c in 0..<Int(source.format.channelCount) {
            output.floatChannelData![c].update(from: source.floatChannelData![c]+from,count: n)
            // Sub-millisecond edge ramps avoid a waveform discontinuity without adding time.
            if soften {
                let edge = min(32,n/4)
                for i in 0..<edge {
                    let gain = Float(i+1)/Float(edge)
                    output.floatChannelData![c][i] *= gain
                    output.floatChannelData![c][n-1-i] *= gain
                }
            }
        }
        return output
    }
    static func decode(_ path: String) throws -> AVAudioPCMBuffer {
        guard let ffmpeg = ["/opt/homebrew/bin/ffmpeg","/usr/local/bin/ffmpeg"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { throw BPMError.message("Smooth loops need FFmpeg installed.") }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gloop-audio-\(UUID()).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let p = Process(); p.executableURL = URL(fileURLWithPath: ffmpeg)
        // Limit decoded memory to about 460 MB; longer media retains VLC playback.
        p.arguments = ["-nostdin","-v","error","-i",path,"-t","1201","-vn","-sn","-dn","-ac","2","-ar","48000","-c:a","pcm_f32le","-y",url.path]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try p.run()
        let timeout = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now()+90,execute: timeout)
        p.waitUntilExit(); timeout.cancel()
        guard p.terminationStatus == 0 else { throw BPMError.message("Could not prepare smooth audio; VLC playback is available.") }
        let file = try AVAudioFile(forReading: url)
        guard file.length > 0, file.length <= 48000*1200 else { throw BPMError.message("Use a section under 20 minutes for smooth loops.") }
        guard let pcm = AVAudioPCMBuffer(pcmFormat: file.processingFormat,frameCapacity: AVAudioFrameCount(file.length)) else { throw BPMError.message("Not enough memory to prepare smooth audio.") }
        try file.read(into: pcm)
        return pcm
    }
    static func selfTest() throws {
        for rate in [1.0,0.75] {
            let audio = GaplessAudio()
            let source = AVAudioPCMBuffer(pcmFormat: audio.format,frameCapacity: 24000)!
            source.frameLength = 24000
            for c in 0..<2 { for i in 0..<24000 { source.floatChannelData![c][i] = Float(0.4*sin(2*Double.pi*440*Double(i)/48000)) } }
            audio.buffer = source; audio.rate = rate
            audio.configure(a: 0,b: 0.5,position: 0,plays: 5)
            try audio.engine.enableManualRenderingMode(.offline,format: audio.format,maximumFrameCount: 256)
            try audio.play()
            let out = AVAudioPCMBuffer(pcmFormat: audio.format,frameCapacity: 256)!
            var samples = [Float]()
            let count = Int(3.0/rate*48000)
            while samples.count < count {
                let result = try audio.engine.renderOffline(min(256,AVAudioFrameCount(count-samples.count)),to: out)
                guard result == .success else { throw BPMError.message("Offline smooth-loop render failed") }
                samples += Array(UnsafeBufferPointer(start: out.floatChannelData![0],count: Int(out.frameLength)))
            }
            // Check every 5 ms window across all four joins, allowing startup/ending latency.
            for boundary in 1...4 {
                let center = Int(Double(boundary)*0.5/rate*48000)
                for offset in stride(from: -2400,through: 2400,by: 120) {
                    let rms = sqrt(samples[(center+offset)..<(center+offset+240)].reduce(0.0) { $0+Double($1*$1) }/240)
                    precondition(rms > 0.05,"Silence at join \(boundary), rate \(rate)")
                }
            }
            precondition(audio.completed == 5,"Wrong finite repeat count")
            audio.pause(); precondition(!audio.isPlaying)
            audio.configure(a: 0.1,b: 0.4,position: 0.2,plays: 0)
            precondition(abs(audio.position-0.2)<0.0001 && audio.completed == 0)
            try audio.play()
            var rendered = 0
            while rendered < 96000 {
                let result = try audio.engine.renderOffline(256,to: out)
                precondition(result == .success)
                rendered += Int(out.frameLength)
            }
            precondition(audio.completed >= 4 && audio.position >= 0.1 && audio.position < 0.4)
            audio.shutdown()
        }
        print("PASS smooth audio: five continuous repeats at 100%/75%, no silent 5 ms windows across joins, finite count, pause, seek and unlimited setup")
    }
}
