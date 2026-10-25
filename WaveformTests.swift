import Foundation
import AVFoundation

func waveformTests() throws {
    let format = AVAudioFormat(standardFormatWithSampleRate: 48000,channels: 2)!
    let pcm = AVAudioPCMBuffer(pcmFormat: format,frameCapacity: 48001)!
    pcm.frameLength = 48001
    for c in 0..<2 { pcm.floatChannelData![c].initialize(repeating: 0,count: 48001) }
    // One-sample transients survive reduction, including opposite-phase stereo and a partial final bin.
    pcm.floatChannelData![0][12000] = 0.5; pcm.floatChannelData![1][12000] = -0.9
    pcm.floatChannelData![1][48000] = -0.8
    let wave = WaveformEnvelope(pcm)
    precondition(wave.peaks.count <= 16384 && wave.peaks.max() == 0.9)
    precondition(wave.peaks[Int(0.25/wave.binDuration)] == 0.9)
    precondition(wave.peaks.last == 0.8 && abs(wave.duration-Double(48001)/48000) < 0.000001)
    precondition(wave.peaks.filter { $0 != 0 }.count == 2,"Silence must remain silent; stereo must not cancel")
    let mono = AVAudioPCMBuffer(pcmFormat: AVAudioFormat(standardFormatWithSampleRate: 44100,channels: 1)!,frameCapacity: 100)!
    mono.frameLength = 100; mono.floatChannelData![0].initialize(repeating: 0,count: 100)
    precondition(WaveformEnvelope(mono).peaks.allSatisfy { $0 == 0 })
    mono.frameLength = 0; precondition(WaveformEnvelope(mono).peaks.isEmpty)
    var scale = WaveformScale(duration: 20); scale.fit()
    precondition(scale.time(at: 0) == 0 && scale.time(at: 1) == 20)
    precondition(scale.time(at: -1) == 0 && scale.time(at: 2) == 20)
    scale.zoom(a: 8,b: 10)
    precondition(scale.lower < 8 && scale.upper > 10 && scale.span < 4)
    for t in [8.0,9,10] { precondition(abs(scale.time(at: scale.fraction(at: t))-t) < 0.000001) }
    scale.zoom(a: 0,b: 1); precondition(scale.lower == 0)
    scale.zoom(a: 19,b: 20); precondition(scale.upper == 20)
    scale.fit(); precondition(scale.lower == 0 && scale.upper == 20)
    let reverse = WaveformScale.selection(9,2,duration: 20)!
    precondition(reverse.0 == 2 && reverse.1 == 9)
    let clipped = WaveformScale.selection(-1,30,duration: 20)!
    precondition(clipped.0 == 0 && clipped.1 == 20)
    precondition(WaveformScale.selection(1,1.1,duration: 20) == nil)
    precondition(WaveformScale.selection(.nan,2,duration: 20) == nil)
    // A peak summary stays small even for a full minute; PCM is not retained by the envelope.
    let large = AVAudioPCMBuffer(pcmFormat: format,frameCapacity: 48000*60)!
    large.frameLength = large.frameCapacity
    for c in 0..<2 { large.floatChannelData![c].initialize(repeating: 0.25,count: Int(large.frameLength)) }
    let start = ProcessInfo.processInfo.systemUptime
    let summary = WaveformEnvelope(large)
    precondition(summary.peaks.count <= 16384 && summary.peaks.allSatisfy { $0 == 0.25 })
    print(String(format:"PASS waveform: stereo/transients/silence/partial bins, bounded memory, zoom mapping, reversed and clamped selection; 60s PCM summarized in %.1f ms",(ProcessInfo.processInfo.systemUptime-start)*1000))
}
