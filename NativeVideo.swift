import AppKit
import AVFoundation

enum VideoState { case stopped, playing, paused, ended, failed }

/// The system player draws video; the prebuffered audio engine owns loop timing.
final class NativeVideo {
    let av = AVPlayer()
    lazy var layer = AVPlayerLayer(player: av)
    private var endObserver: NSObjectProtocol?
    private var ended = false
    private var speed: Float = 1
    var rate: Float { speed }
    var isPlaying: Bool { av.rate != 0 && !ended && av.currentItem?.status != .failed }
    var time: Double { let s = av.currentTime().seconds; return s.isFinite ? max(0, s) : 0 }
    var duration: Double { let s = av.currentItem?.duration.seconds ?? 0; return s.isFinite ? max(0, s) : 0 }
    var hasVideo: UInt32 { layer.isReadyForDisplay ? 1 : 0 }
    var state: VideoState {
        if av.currentItem?.status == .failed { return .failed }
        if ended { return .ended }
        if av.currentItem == nil { return .stopped }
        return isPlaying ? .playing : .paused
    }
    init() { av.automaticallyWaitsToMinimizeStalling = false }
    func open(_ url: URL) {
        stop()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        let item = AVPlayerItem(url: url); item.audioTimePitchAlgorithm = .timeDomain
        av.replaceCurrentItem(with: item)
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in self?.ended = true }
    }
    func play() { ended = false; av.playImmediately(atRate: speed) }
    func pause(_ paused: Bool) { if paused { av.pause() } else { play() } }
    func stop() { av.pause(); ended = false; av.currentItem?.cancelPendingSeeks() }
    func seek(_ seconds: Double) {
        guard seconds.isFinite else { return }
        ended = false
        av.seek(to: CMTime(seconds: max(0, seconds), preferredTimescale: 60000), toleranceBefore: .zero, toleranceAfter: .zero)
    }
    func setRate(_ rate: Float) { speed = rate; if isPlaying { av.rate = rate } }
    func setVolume(_ percent: Int32) { av.volume = Float(min(100, max(0, percent))) / 100 }
    func shutdown() {
        stop(); av.replaceCurrentItem(with: nil)
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
    }
}

enum NativeAudio {
    private final class Loaded<T>: @unchecked Sendable {
        let lock = NSLock()
        var result: Result<T, Error>?
        func store(_ value: Result<T, Error>) { lock.lock(); result = value; lock.unlock() }
        func take() -> Result<T, Error>? { lock.lock(); defer { lock.unlock() }; return result }
    }
    // Call on the decoder/import worker queue (or a headless test), never UI callbacks.
    private static func load<T>(_ operation: @escaping () async throws -> T) throws -> T {
        let semaphore = DispatchSemaphore(value: 0), box = Loaded<T>()
        let task = Task.detached {
            do { box.store(.success(try await operation())) } catch { box.store(.failure(error)) }
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + 30) == .success, let result = box.take() else {
            task.cancel(); throw BPMError.message("Reading this video timed out. Try a local MP4/MOV copy.")
        }
        return try result.get()
    }
    /// Decode using Apple codecs, with a strict duration/memory bound.
    static func decode(_ path: String, sampleRate: Double, channels: UInt32, limit: Double, truncate: Bool = false) throws -> AVAudioPCMBuffer {
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        let duration = try load { try await asset.load(.duration).seconds }
        guard duration.isFinite, duration > 0 else { throw BPMError.message("Could not read the audio duration.") }
        guard truncate || duration <= limit else { throw BPMError.message("Buffered loops support videos up to 20 minutes. Longer videos use regular playback.") }
        guard let track = try load({ try await asset.loadTracks(withMediaType: .audio).first }) else { throw BPMError.message("This video has no audio track. Video playback is still available.") }
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: min(duration, limit), preferredTimescale: 60000))
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: true
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw BPMError.message("This audio format is not supported. Convert the video to MP4 with AAC audio.") }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? BPMError.message("Could not read this audio track.") }
        defer { reader.cancelReading() }
        let capacity = Int(ceil(min(duration, limit) * sampleRate)) + 4096
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels),
              let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(capacity)), let target = pcm.floatChannelData else { throw BPMError.message("Not enough memory to prepare this audio.") }
        let destination = AudioBufferList.allocate(maximumBuffers: Int(channels))
        defer { free(destination.unsafeMutablePointer) }
        var frames = 0
        while let sample = output.copyNextSampleBuffer() {
            let count = CMSampleBufferGetNumSamples(sample)
            guard count <= Int(Int32.max), frames + count <= capacity else { throw BPMError.message("Audio exceeds the supported buffer size.") }
            for channel in 0..<Int(channels) {
                destination[channel] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(count * MemoryLayout<Float>.size), mData: target[channel] + frames)
            }
            // Decode directly into planar PCM; avoid a temporary interleaved array
            // and a Swift channel/sample loop for every packet.
            let result = CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: Int32(count), into: destination.unsafeMutablePointer)
            guard result == noErr else { throw BPMError.message("Could not decode this audio.") }
            frames += count
        }
        guard reader.status == .completed, frames > 0 else { throw reader.error ?? BPMError.message("Could not finish decoding this audio.") }
        pcm.frameLength = AVAudioFrameCount(frames)
        return pcm
    }
    static func duration(_ url: URL) throws -> Double {
        let asset = AVURLAsset(url: url)
        let (time, playable) = try load { try await asset.load(.duration, .isPlayable) }
        let hasVideo = try load { try await !asset.loadTracks(withMediaType: .video).isEmpty }
        let duration = time.seconds
        guard duration.isFinite, duration > 0, playable, hasVideo else { throw BPMError.message("This file cannot be opened by macOS. Use an MP4 or MOV with H.264/HEVC video and AAC audio, or File → Convert Video to MP4.") }
        return duration
    }
}
