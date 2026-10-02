// Compile with AudioVisualizerService.swift, PlaybackBars.swift and PremiumControls.swift.
// Uses generated PCM, never the microphone or system playback.
import AppKit
import CoreAudio
import SwiftUI

@main struct VisualizerChecks {
    static func spectrum(chunk: Int, rate: Double = 48_000, frequency: Double = 1_000,
                         stereo: Bool = false, amplitude: Float = 0.4, pulsed: Bool = false) -> [[CGFloat]] {
        var readings: [[CGFloat]] = []
        let analyzer = SpectrumAnalyzer(count: 72) { readings.append($0) }
        let channels = stereo ? 2 : 1
        let format = AudioStreamBasicDescription(mSampleRate: rate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(4 * channels), mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(4 * channels), mChannelsPerFrame: UInt32(channels),
            mBitsPerChannel: 32, mReserved: 0)
        let total = Int(rate) * (pulsed ? 4 : 1)
        for start in stride(from: 0, to: total, by: chunk) {
            var pcm = (start..<min(start + chunk, total)).flatMap { frame -> [Float] in
                // Half a second of tone, then half a second of silence.
                let sample: Float
                if pulsed {
                    let time = Double(frame) / rate
                    let envelope = 0.35 + 0.65 * exp(-time.truncatingRemainder(dividingBy: 0.4) * 20)
                    let frequencies: [Double] = [80, 160, 440, 880, 1_760, 3_520, 7_040]
                    let mix = frequencies.reduce(0.0) { $0 + sin(2 * .pi * $1 * time) } / Double(frequencies.count)
                    sample = amplitude * Float(mix * envelope)
                } else {
                    sample = frame < total / 2 ? amplitude * Float(sin(2 * .pi * frequency * Double(frame) / rate)) : 0
                }
                return Array(repeating: sample, count: channels)
            }
            pcm.withUnsafeMutableBytes { bytes in
                var list = AudioBufferList(mNumberBuffers: 1,
                    mBuffers: AudioBuffer(mNumberChannels: UInt32(channels),
                        mDataByteSize: UInt32(bytes.count), mData: bytes.baseAddress))
                analyzer.process(bufferList: &list, format: format)
            }
        }
        return readings
    }

    @MainActor static func main() throws {
        let suite = "notch.visualizer.check.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "audioVisualizerNeedsRetry")
        let blocked = AudioVisualizerService(defaults: defaults)
        precondition(blocked.needsRetry && blocked.error != nil)
        blocked.setActive(true)
        blocked.setActive(false)
        blocked.stop()
        precondition(AudioVisualizerService(defaults: defaults).needsRetry,
                     "Stopping/relaunching must not retry a failed audio permission request")
        blocked.retry()
        precondition(!blocked.needsRetry && blocked.error == nil)
        precondition(!AudioVisualizerService(defaults: defaults).needsRetry,
                     "An explicit retry should clear the persisted failure")
        print("PASS: audio failure persists across service recreation; explicit retry clears it")
        let small = spectrum(chunk: 128)
        let large = spectrum(chunk: 2_048)
        precondition(small.count > 50 && small.count <= 60, "Expected approximately 60 audio updates per second")
        precondition(small == large, "Callback size must not alter the spectrum")
        precondition(small == spectrum(chunk: 512, stereo: true), "Stereo mixing differs from mono")
        let tone = small[20]
        let peak = tone.enumerated().max(by: { $0.element < $1.element })!.offset
        let peakFrequency = exp(log(48.0) + log(16_000.0 / 48.0) * (Double(peak) + 0.5) / 72)
        precondition(abs(peakFrequency - 1_000) < 120, "FFT peak does not follow the tone")
        precondition(tone.max()! > 0.65, "Tone should produce a visible peak")
        precondition(tone.filter { $0 > 0.5 }.count < 12, "An isolated tone must not become a solid block")
        precondition(small.last!.max()! < 0.003, "Silence must settle to dots")
        precondition(spectrum(chunk: 128, amplitude: 0).allSatisfy { $0.allSatisfy { $0 == 0 } }, "Silence must not animate")
        let quiet = spectrum(chunk: 128, amplitude: 0.02)[20]
        precondition(quiet.max()! < tone.max()! - 0.2, "Bars must respond to amplitude")
        let high = spectrum(chunk: 256, rate: 44_100, frequency: 6_000)[20]
        precondition(high.enumerated().max(by: { $0.element < $1.element })!.offset > peak + 15,
                     "Frequency changes must move the peak")
        precondition((small + [high, quiet]).allSatisfy { $0.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 } })
        print("PASS: callback independence, stereo, sample rates, frequency, dynamics, silence, finite range")
        var compact = CompactSpectrum()
        let beatFrames = spectrum(chunk: 256, amplitude: 0.9, pulsed: true).map {
            compact.scales(playing: true, levels: $0)
        }
        let settled = Array(beatFrames.dropFirst(60))
        let ranges = (0..<5).map { index -> CGFloat in
            let values = settled.map { $0[index] }
            return values.max()! - values.min()!
        }
        precondition(ranges.allSatisfy { $0 > 0.22 }, "Dense PCM beats must move every compact band")
        let averageHeight = settled.flatMap { $0 }.reduce(0, +) / CGFloat(settled.count * 5)
        precondition(averageHeight > 0.3 && averageHeight < 0.75, "Audible music needs visible midrange bars")
        let floorFraction = Double(settled.flatMap { $0 }.filter { $0 < 0.22 }.count) / Double(settled.count * 5)
        precondition(floorFraction < 0.1, "Audible music must not disappear into dots")
        let ceilingFraction = Double(settled.flatMap { $0 }.filter { $0 > 0.9 }.count) / Double(settled.count * 5)
        precondition(ceilingFraction < 0.2, "Compact bars must not remain near maximum")
        print("PASS: dense PCM beat motion; per-bar ranges \(ranges.map { String(format: "%.2f", Double($0)) }); mean height \(Int(averageHeight * 100))%; near-floor \(Int(floorFraction * 100))%, near-ceiling \(Int(ceilingFraction * 100))%")


        if CommandLine.arguments.count > 1 {
            // Deliberately synthetic visual fixture for checking spacing and clipping.
            let fixture = (0..<72).map { index -> CGFloat in
                let x = Double(index) / 71
                let envelope = exp(-pow((x - 0.15) / 0.09, 2)) * 0.85
                    + exp(-pow((x - 0.42) / 0.06, 2)) * 0.45
                    + exp(-pow((x - 0.78) / 0.12, 2)) * 0.95
                return CGFloat(envelope * (0.35 + abs(sin(Double(index) * 1.9)) * 0.65))
            }
            let content = VStack(spacing: 22) {
                HoverWaveform(progress: 0.45, levels: fixture).frame(width: 356, height: 26)
                HoverWaveform(progress: 0.45, levels: tone).frame(width: 356, height: 26)
                HoverWaveform(progress: 0.45, levels: small.last!).frame(width: 356, height: 26)
            }.padding(24).background(.black)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 3
            guard let image = renderer.cgImage else { fatalError("Native rendering failed") }
            let bitmap = NSBitmapImageRep(cgImage: image)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
            print("Rendered design fixture, real FFT tone, and silence")
        }
    }
}
