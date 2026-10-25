import Foundation
import AVFoundation
import Darwin
import CryptoKit

func usage() -> rusage { var value = rusage(); getrusage(RUSAGE_SELF, &value); return value }
func cpu(_ value: rusage) -> Double { Double(value.ru_utime.tv_sec + value.ru_stime.tv_sec) + Double(value.ru_utime.tv_usec + value.ru_stime.tv_usec) / 1e6 }
func measured(_ work: () throws -> Void) rethrows -> [String: Double] {
    let before = usage(), start = ProcessInfo.processInfo.systemUptime
    try work()
    let after = usage()
    return ["wall_ms": (ProcessInfo.processInfo.systemUptime - start) * 1000,
            "cpu_ms": (cpu(after) - cpu(before)) * 1000]
}
let args = CommandLine.arguments
precondition(args.count == 3, "Usage: profile <prepare|bpm|fingerprint> <media path>")
var report: [String: Any] = [:]
if args[1] == "bpm" {
    var pcm: AVAudioPCMBuffer!
    report["decode"] = try measured { pcm = try NativeAudio.decode(args[2], sampleRate: 11025, channels: 1, limit: 90, truncate: true) }
    let samples = Array(UnsafeBufferPointer(start: pcm.floatChannelData![0], count: Int(pcm.frameLength)))
    report["estimate"] = measured {
        do { let result = try BPMDetector.estimate(samples); report["bpm"] = result.bpm }
        catch { report["estimate_error"] = error.localizedDescription }
    }
} else {
    var pcm: AVAudioPCMBuffer!
    report["decode"] = try measured { pcm = try GaplessAudio.decode(args[2]) }
    report["seconds"] = Double(pcm.frameLength) / pcm.format.sampleRate
    if args[1] == "fingerprint" {
        var digest = SHA256()
        for channel in 0..<Int(pcm.format.channelCount) {
            digest.update(data: Data(bytes: pcm.floatChannelData![channel], count: Int(pcm.frameLength) * MemoryLayout<Float>.size))
        }
        report["pcm_sha256"] = digest.finalize().map { String(format: "%02x", $0) }.joined()
    } else {
        let audio = GaplessAudio(); audio.buffer = pcm
        report["configure_first"] = measured { audio.configure(a: 0, b: audio.duration, position: 0, plays: 30) }
        report["configure_repeat"] = (0..<5).map { _ in measured { audio.configure(a: 0, b: audio.duration, position: 0, plays: 30) } }
        report["configure_seek"] = measured { audio.configure(a: 0, b: audio.duration, position: audio.duration / 2, plays: 30) }
        audio.shutdown()
    }
}
report["peak_rss_mib"] = Double(usage().ru_maxrss) / 1048576
let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
print(String(decoding: data, as: UTF8.self))
