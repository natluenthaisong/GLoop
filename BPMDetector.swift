import Foundation
import Accelerate

struct BPMEstimate {
    let bpm: Double
    let strength: Double
    let seconds: Double
    var description: String { seconds < 8 || strength < 0.25 ? "Estimate · weak / short rhythm" : "Estimate · check half / double time" }
}
enum BPMError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let s) = self { return s }; return nil }
}
enum BPMDetector {
    static let sampleRate = 11025.0
    static func detect(path: String) throws -> BPMEstimate {
        let pcm = try NativeAudio.decode(path, sampleRate: sampleRate, channels: 1, limit: 90, truncate: true)
        let samples = Array(UnsafeBufferPointer(start: pcm.floatChannelData![0], count: Int(pcm.frameLength)))
        return try estimate(samples)
    }
    static func estimate(_ samples: [Float]) throws -> BPMEstimate {
        let n = 1024, hop = 128
        let seconds = Double(samples.count)/sampleRate
        guard seconds >= 4 else { throw BPMError.message("Clip is too short for a useful estimate. Use a longer clip or enter BPM.") }
        guard let fft = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(n), .FORWARD) else { throw BPMError.message("Could not initialize audio analysis.") }
        defer { vDSP_DFT_DestroySetup(fft) }
        let window = (0..<n).map { Float(0.5-0.5*cos(2*Double.pi*Double($0)/Double(n-1))) }
        var input = [Float](repeating: 0,count: n), imaginary = input, real = input, imag = input
        var previous = [Float](repeating: 0,count: n/2)
        var onset: [Double] = []
        for start in stride(from: 0, through: samples.count-n, by: hop) {
            for j in 0..<n { input[j] = samples[start+j].isFinite ? samples[start+j]*window[j] : 0 }
            vDSP_DFT_Execute(fft, input, imaginary, &real, &imag)
            var flux = 0.0
            for bin in 5..<(n/2-20) {
                let magnitude = log1p(sqrt(real[bin]*real[bin]+imag[bin]*imag[bin])*10)
                flux += Double(max(0,magnitude-previous[bin])); previous[bin] = magnitude
            }
            onset.append(flux)
        }
        let frameRate = sampleRate/Double(hop)
        let radius = Int(frameRate*0.18)
        var envelope = onset
        for i in onset.indices {
            let lo = max(0,i-radius), hi = min(onset.count,i+radius+1)
            let average = onset[lo..<hi].reduce(0,+)/Double(hi-lo)
            envelope[i] = max(0,onset[i]-average)
        }
        // Ignore the initial FFT warm-up impulse, which is not a musical onset.
        for i in 0..<min(8,envelope.count) { envelope[i] = 0 }
        let energy = envelope.reduce(0) { $0+$1*$1 }
        guard energy > 0.001 else { throw BPMError.message("No clear rhythmic pulse found. Enter BPM manually.") }
        let minLag = Int(frameRate*60/240), maxLag = min(Int(frameRate*60/55),envelope.count/3)
        guard maxLag > minLag else { throw BPMError.message("Not enough rhythmic audio to estimate BPM.") }
        var correlations = [Double](repeating: 0,count: maxLag+2)
        for lag in 1..<(maxLag+2) {
            var sum = 0.0, a = 0.0, b = 0.0
            for i in lag..<envelope.count { sum += envelope[i]*envelope[i-lag]; a += envelope[i]*envelope[i]; b += envelope[i-lag]*envelope[i-lag] }
            correlations[lag] = sum / max(1e-12,sqrt(a*b))
        }
        let peaks = (minLag...maxLag).filter { correlations[$0] >= correlations[$0-1] && correlations[$0] > correlations[$0+1] }
        guard let strongest = peaks.max(by: { correlations[$0] < correlations[$1] }), correlations[strongest] > 0.08 else { throw BPMError.message("No stable pulse found. Try a longer section or enter BPM.") }
        if ProcessInfo.processInfo.arguments.contains("--bpm-debug") { print(peaks.map { (sampleRate/Double(hop)*60/Double($0), correlations[$0]) }) }
        // Prefer the earliest strong periodic peak to avoid counting every other beat.
        let lag = peaks.first(where: { correlations[$0] >= correlations[strongest]*0.8 }) ?? strongest
        let left = correlations[lag-1], center = correlations[lag], right = correlations[lag+1]
        let denominator = left-2*center+right
        let correction = abs(denominator) > 1e-8 ? max(-0.5,min(0.5,0.5*(left-right)/denominator)) : 0
        let bpm = frameRate*60/(Double(lag)+correction)
        guard bpm >= 55 && bpm <= 240 else { throw BPMError.message("Pulse is outside the detector's 55–240 BPM range. Enter BPM manually.") }
        return BPMEstimate(bpm: (bpm*10).rounded()/10, strength: center, seconds: seconds)
    }
    static func selfTest() throws {
        for bpm in [60.0,90,120,180,212] {
            var signal = [Float](repeating: 0,count: Int(sampleRate*16))
            for beat in stride(from: 0.4, to: 15.8, by: 60/bpm) {
                let start = Int(beat*sampleRate)
                for j in 0..<min(700,signal.count-start) {
                    signal[start+j] += Float(exp(-Double(j)/110)*sin(2*Double.pi*700*Double(j)/sampleRate))
                }
            }
            let result = try estimate(signal)
            precondition(abs(result.bpm-bpm) < 2, "Expected \(bpm), got \(result.bpm)")
            print("PASS pulse \(bpm) → \(result.bpm) BPM")
        }
        do { _ = try estimate([Float](repeating: 0,count: 110250)); preconditionFailure("Silence should fail") } catch is BPMError {}
        do { _ = try estimate([Float](repeating: 1,count: 11025)); preconditionFailure("Short audio should fail") } catch is BPMError {}
        print("PASS silence and short audio rejection")
    }
}
