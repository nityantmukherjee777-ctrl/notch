import AppKit
import Testing
@testable import Notch

@Suite @MainActor struct CompactVisualizerTests {
    @Test func compactBarsFollowIndependentAudioBands() {
        var meter = CompactSpectrum()
        let quiet = meter.scales(playing: true, levels: Array(repeating: 0, count: 72))
        #expect(quiet == Array(repeating: 0.14, count: 5))
        var bass = Array<CGFloat>(repeating: 0, count: 72)
        bass[3] = 0.9
        let bassBars = meter.scales(playing: true, levels: bass)
        #expect(bassBars[0] > 0.6)
        #expect(bassBars[4] == 0.14)
        var treble = Array<CGFloat>(repeating: 0, count: 72)
        treble[63] = 0.9
        let trebleBars = meter.scales(playing: true, levels: treble)
        #expect(trebleBars[4] > 0.6)
        #expect(trebleBars[0] == 0.14)
        #expect(meter.scales(playing: false, levels: bass) == [0.18, 0.28, 0.36, 0.26, 0.18])
    }

    @Test func sustainedLoudAudioSettlesInsteadOfStayingMaxed() {
        var meter = CompactSpectrum()
        var output: [CGFloat] = []
        for _ in 0..<240 {
            output = meter.scales(playing: true, levels: Array(repeating: 1, count: 72))
        }
        #expect(output.allSatisfy { $0 < 0.8 && $0 > 0.6 })
        let dip = meter.scales(playing: true, levels: Array(repeating: 0.75, count: 72))
        #expect(dip.allSatisfy { $0 > 0.5 && $0 < output[0] })
        let softer = meter.scales(playing: true, levels: Array(repeating: 0.2, count: 72))
        #expect(softer.allSatisfy { $0 > 0.3 && $0 < 0.5 })
        let quiet = meter.scales(playing: true, levels: Array(repeating: 0, count: 72))
        #expect(quiet == CompactSpectrum.silence)
        let invalid = meter.scales(playing: true, levels: Array(repeating: CGFloat.nan, count: 72))
        #expect(invalid == CompactSpectrum.silence)
    }

    @Test func compressedBeatsRiseAndDropWithoutSyntheticMotion() {
        var meter = CompactSpectrum()
        var heights: [CGFloat] = []
        for frame in 0..<480 {
            // Sustained loud bed with short transients: no silent gaps needed.
            let phase = frame % 30
            let level: CGFloat = 0.74 + (phase < 8 ? 0.22 * CGFloat(8 - phase) / 8 : 0)
            let output = meter.scales(playing: true, levels: Array(repeating: level, count: 72))
            if frame >= 120 { heights.append(output[0]) }
        }
        #expect((heights.max() ?? 0) - (heights.min() ?? 1) > 0.25)
        #expect(heights.allSatisfy { $0 > 0.5 })
        #expect(heights.filter { $0 > 0.9 }.count < heights.count / 5)
        var steady: [CGFloat] = []
        for _ in 0..<480 {
            steady = meter.scales(playing: true, levels: Array(repeating: 0.74, count: 72))
        }
        let unchanged = meter.scales(playing: true, levels: Array(repeating: 0.74, count: 72))
        #expect(abs(steady[0] - unchanged[0]) < 0.0001)
    }

    @Test func artworkColorUsesGrayForBlackAndColorForBlue() {
        func image(_ color: NSColor) -> NSImage {
            NSImage(size: NSSize(width: 24, height: 24), flipped: false) { rect in
                color.setFill(); rect.fill(); return true
            }
        }
        let black = ArtworkAccent.color(for: image(.black)).usingColorSpace(.deviceRGB)!
        #expect(abs(black.redComponent - black.greenComponent) < 0.01)
        #expect(abs(black.greenComponent - black.blueComponent) < 0.01)
        #expect(black.brightnessComponent > 0.5)
        let blue = ArtworkAccent.color(for: image(.systemBlue)).usingColorSpace(.deviceRGB)!
        #expect(blue.blueComponent > blue.redComponent)
        #expect(blue.blueComponent > blue.greenComponent)
    }
}
