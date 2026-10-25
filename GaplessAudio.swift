import Foundation
import AVFoundation

/// PCM is queued before playback. A repeat never stops or seeks the audio node.
final class GaplessAudio {
    struct PreparedPhrase {
        let source: AVAudioPCMBuffer
        let lo: Int, hi: Int
        let pcm: AVAudioPCMBuffer
    }
    let engine = AVAudioEngine()
    let node = AVAudioPlayerNode()
    let stretch = AVAudioUnitTimePitch()
    let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
    var buffer: AVAudioPCMBuffer? { didSet { phraseCache = nil } }
    private var phraseCache: PreparedPhrase?
    private var held: [AVAudioPCMBuffer] = []
    private var start = 0.0, end = 0.0, firstStart = 0.0, firstLength = 0.0
    private var limit = 0
    private var cachedTime = 0.0
    var configured = false
    var ready: Bool { buffer != nil }
    var isPlaying: Bool { node.isPlaying }
    var duration: Double { Double(buffer?.frameLength ?? 0)/format.sampleRate }
    var rate: Double { get { Double(stretch.rate) } set { stretch.rate = Float(newValue) } }
    /// AVAudioUnitTimePitch expresses pitch in cents (100 cents = one semitone).
    var pitchSemitones: Int {
        get { Int((stretch.pitch / 100).rounded()) }
        set { stretch.pitch = Float(min(12,max(-12,newValue))) * 100 }
    }
    var volume: Float { get { node.volume } set { node.volume = newValue } }
    init() {
        engine.attach(node); engine.attach(stretch)
        engine.connect(node,to: stretch,format: format)
        engine.connect(stretch,to: engine.mainMixerNode,format: format)
        stretch.overlap = 8
    }
    func clear() { node.stop(); pitchSemitones = 0; buffer = nil; held = []; configured = false; cachedTime = 0 }
    func shutdown() { clear(); engine.stop() }
    static func prepare(_ source: AVAudioPCMBuffer, a: Double, b: Double) -> PreparedPhrase {
        let lo = max(0,min(Int(a*48000),Int(source.frameLength)-1))
        let hi = min(Int(source.frameLength),max(lo+1,Int((b*48000).rounded())))
        return PreparedPhrase(source: source,lo: lo,hi: hi,pcm: slice(source,from: lo,to: hi,soften: true))
    }
    func install(_ prepared: PreparedPhrase) {
        buffer = prepared.source
        phraseCache = prepared
    }
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
        let phrase: AVAudioPCMBuffer
        if let cached = phraseCache, cached.lo == lo && cached.hi == hi { phrase = cached.pcm }
        else {
            // Drop the old phrase before allocating its replacement.
            phraseCache = nil
            phrase = Self.slice(buffer,from: lo,to: hi,soften: true)
            phraseCache = PreparedPhrase(source: buffer,lo: lo,hi: hi,pcm: phrase)
        }
        let first = Self.firstBuffers(source: buffer, phrase: phrase, lo: lo, pos: pos, hi: hi)
        held = first + [phrase]
        for part in first { node.scheduleBuffer(part,at: nil,options: []) }
        if plays == 0 { node.scheduleBuffer(phrase,at: nil,options: .loops) }
        else if plays > 1 { for _ in 1..<plays { node.scheduleBuffer(phrase,at: nil,options: []) } }
        configured = true
    }
    func play() throws { if !engine.isRunning { try engine.start() }; node.play() }
    func pause() { _ = consumed; node.pause() }
    /// Keep the prepared phrase alive for the duration of the scheduled view.
    static func view(_ source: AVAudioPCMBuffer, from: Int, to: Int) -> AVAudioPCMBuffer {
        let list = AudioBufferList.allocate(maximumBuffers: Int(source.format.channelCount))
        defer { free(list.unsafeMutablePointer) }
        for channel in 0..<list.count {
            list[channel] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32((to-from) * MemoryLayout<Float>.size), mData: source.floatChannelData![channel] + from)
        }
        let view = AVAudioPCMBuffer(pcmFormat: source.format, bufferListNoCopy: list.unsafePointer, deallocator: { [source] _ in withExtendedLifetime(source) {} })!
        view.frameLength = AVAudioFrameCount(to-from)
        return view
    }
    static func firstBuffers(source: AVAudioPCMBuffer, phrase: AVAudioPCMBuffer, lo: Int, pos: Int, hi: Int) -> [AVAudioPCMBuffer] {
        if pos == lo { return [phrase] }
        let count = hi-pos
        // Small tails need different ramp lengths; copying them is inexpensive.
        if count < 128 { return [slice(source,from: pos,to: hi,soften: true)] }
        let leading = slice(source,from: pos,to: pos+32,soften: false)
        for channel in 0..<Int(source.format.channelCount) {
            for i in 0..<32 { leading.floatChannelData![channel][i] *= Float(i+1)/32 }
        }
        // The cached phrase already has its end ramp. Only the new 32-frame
        // onset is copied; the remaining minutes are a retained, read-only view.
        return [leading, view(phrase,from: pos-lo+32,to: hi-lo)]
    }
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
        try NativeAudio.decode(path, sampleRate: 48000, channels: 2, limit: 1200)
    }
    static func selfTest() throws {
        // A split onset + retained view must be sample-identical to the old
        // copied partial phrase, including overlapping/very short edge ramps.
        let source = AVAudioPCMBuffer(pcmFormat: AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!, frameCapacity: 1000)!
        source.frameLength = 1000
        for c in 0..<2 { for i in 0..<1000 { source.floatChannelData![c][i] = Float(i+1) / Float(1000+c) } }
        for lo in [0,37] {
            let hi = 950, phrase = slice(source,from: lo,to: hi,soften: true)
            for pos in [lo,lo+1,lo+31,hi-128,hi-127,hi-32,hi-1] {
                let expected = slice(source,from: pos,to: hi,soften: true)
                let parts = firstBuffers(source: source,phrase: phrase,lo: lo,pos: pos,hi: hi)
                for c in 0..<2 {
                    let actual = parts.flatMap { Array(UnsafeBufferPointer(start: $0.floatChannelData![c],count: Int($0.frameLength))) }
                    precondition(actual == Array(UnsafeBufferPointer(start: expected.floatChannelData![c],count: Int(expected.frameLength))), "Partial phrase changed samples")
                }
            }
        }
        let cached = GaplessAudio(); cached.buffer = source
        cached.configure(a: 0,b: 0.02,position: 0,plays: 5)
        let firstPhrase = cached.phraseCache!.pcm
        cached.configure(a: 0,b: 0.02,position: 0.01,plays: 30)
        precondition(cached.phraseCache!.pcm === firstPhrase, "Unchanged loop must reuse its phrase")
        cached.configure(a: 0,b: 0.015,position: 0,plays: 5)
        precondition(cached.phraseCache!.pcm !== firstPhrase, "Changed loop must invalidate its phrase")
        cached.buffer = source; precondition(cached.phraseCache == nil)
        let prepared = prepare(source,a: 0,b: 0.02)
        cached.install(prepared); cached.configure(a: 0,b: 0.02,position: 0,plays: 5)
        precondition(cached.phraseCache!.pcm === prepared.pcm, "Prepared phrase must survive installation")
        cached.clear(); precondition(cached.phraseCache == nil)
        weak var backing: AVAudioPCMBuffer?
        let retained = autoreleasepool { () -> AVAudioPCMBuffer in
            let temporary = slice(source,from: 10,to: 500,soften: false)
            backing = temporary
            return view(temporary,from: 20,to: 200)
        }
        precondition(backing != nil && retained.floatChannelData![0][0] == source.floatChannelData![0][30], "Scheduled view must retain its backing samples")
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
            audio.configure(a: 0.1,b: 0.4,position: 0.2,plays: 5)
            try audio.play()
            var tail = [Float]()
            while tail.count < Int(1.6/rate*48000) {
                let result = try audio.engine.renderOffline(256,to: out)
                precondition(result == .success)
                tail += Array(UnsafeBufferPointer(start: out.floatChannelData![0],count: Int(out.frameLength)))
            }
            precondition(audio.completed == 5 && abs(audio.position-0.4) < 0.0001)
            for boundary in 0...3 {
                let center = Int((0.2+Double(boundary)*0.3)/rate*48000)
                for offset in stride(from: -960,through: 960,by: 120) {
                    let rms = sqrt(tail[(center+offset)..<(center+offset+240)].reduce(0.0) { $0+Double($1*$1) }/240)
                    precondition(rms > 0.05, "Silence after a partial first phrase")
                }
            }
            audio.shutdown()
        }
        print("PASS smooth audio: retained-view samples/lifetime, cache invalidation, full/partial continuous repeats at 100%/75%, finite count, pause, seek and unlimited setup")
    }
}
