import Foundation
import AVFoundation

extension GaplessAudio {
    static func pitchTest() throws {
        let sourceHz = 329.6275569 // E4; independent of the player's speed.
        for rate in [1.0,0.75] {
            for shift in [-12,-1,0,1,12] {
                let audio = GaplessAudio()
                let source = AVAudioPCMBuffer(pcmFormat: audio.format,frameCapacity: 48000)!
                source.frameLength = 48000
                for c in 0..<2 { for i in 0..<48000 { source.floatChannelData![c][i] = Float(0.4*sin(2*Double.pi*sourceHz*Double(i)/48000)) } }
                audio.buffer = source; audio.rate = rate; audio.pitchSemitones = shift
                audio.configure(a: 0,b: 1,position: 0,plays: 3)
                precondition(audio.pitchSemitones == shift && abs(audio.rate-rate) < 0.001,"Configuring a loop changed pitch or speed")
                try audio.engine.enableManualRenderingMode(.offline,format: audio.format,maximumFrameCount: 512)
                try audio.play()
                let output = AVAudioPCMBuffer(pcmFormat: audio.format,frameCapacity: 512)!
                var samples = [Float]()
                while samples.count < Int(3.3/rate*48000) {
                    guard try audio.engine.renderOffline(512,to: output) == .success else { throw BPMError.message("Pitch render failed") }
                    samples += Array(UnsafeBufferPointer(start: output.floatChannelData![0],count: Int(output.frameLength)))
                }
                // Interpolated rising zero crossings over a settled half-second.
                var crossings = [Double]()
                for i in 24001..<48000 where samples[i-1] <= 0 && samples[i] > 0 {
                    crossings.append(Double(i-1)+Double(-samples[i-1])/Double(samples[i]-samples[i-1]))
                }
                guard crossings.count > 20 else { throw BPMError.message("Pitch test output is silent") }
                let measured = Double(crossings.count-1)*48000/(crossings.last!-crossings.first!)
                let expected = sourceHz*pow(2,Double(shift)/12)
                precondition(abs(1200*log2(measured/expected)) < 12,"Wrong pitch: \(measured) Hz, expected \(expected), rate \(rate)")
                precondition(audio.completed == 3 && abs(audio.position-1) < 0.001,"Pitch changed loop duration/count")
                for boundary in 1...2 {
                    let center = Int(Double(boundary)/rate*48000)
                    for offset in stride(from: -2400,through: 2400,by: 120) {
                        let rms = sqrt(samples[(center+offset)..<(center+offset+240)].reduce(0.0) { $0+Double($1*$1) }/240)
                        precondition(rms > 0.035,"Silent gap at pitched loop boundary")
                    }
                }
                // Changing pitch never restarts the audio clock, resets loop counts, or changes speed.
                let position = audio.position, completed = audio.completed, wasPlaying = audio.isPlaying
                audio.pitchSemitones = 1
                precondition(audio.position == position && audio.completed == completed && audio.isPlaying == wasPlaying && abs(audio.rate-rate) < 0.001)
                audio.pitchSemitones = 0
                precondition(audio.stretch.pitch == 0)
                audio.clear(); precondition(audio.pitchSemitones == 0)
                audio.shutdown()
                print(String(format:"PASS pitch %+d at %.0f%%: %.2f Hz; 3 loops without silent joins",shift,rate*100,measured))
            }
        }
    }
}
