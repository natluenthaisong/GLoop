import Foundation

enum ReleaseTests {
    static func media(_ url: URL) throws {
        let seconds = try NativeAudio.duration(url)
        let pcm = try GaplessAudio.decode(url.path)
        precondition(pcm.format.sampleRate == 48000 && pcm.format.channelCount == 2)
        precondition(abs(Double(pcm.frameLength) / 48000 - seconds) < 0.15)
        let mono = try NativeAudio.decode(url.path, sampleRate: 11025, channels: 1, limit: 1, truncate: true)
        precondition(mono.frameLength > 10000 && mono.frameLength < 13000)
        do { _ = try NativeAudio.decode(url.path, sampleRate: 48000, channels: 2, limit: 0.1); preconditionFailure("Long decode must be bounded") } catch is BPMError {}
        let silentFolder = FileManager.default.temporaryDirectory.appendingPathComponent("GLoop-invalid-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: silentFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: silentFolder) }
        let corrupt = silentFolder.appendingPathComponent("bad.mp4")
        try Data("not a movie".utf8).write(to: corrupt)
        do { _ = try NativeAudio.duration(corrupt); preconditionFailure("Corrupt movie must fail") } catch {}
        print("PASS: native stereo/mono decoding, resampling, duration, bounded reads and corrupt video rejection")
    }
}
