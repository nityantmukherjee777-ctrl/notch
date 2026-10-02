import AppKit
import SwiftUI
import QuartzCore

/// The compact five-bar silhouette follows the same live spectrum as the
/// expanded scrubber. No synthetic or repeating animation is used.
struct AudioPlaybackBars: View {
    @ObservedObject var visualizer: AudioVisualizerService
    var playing: Bool
    var color: NSColor

    var body: some View {
        PlaybackBars(playing: playing, tint: Color(nsColor: color), levels: visualizer.compactLevels)
    }
}

private struct PlaybackBars: NSViewRepresentable {
    var playing: Bool
    var tint: Color
    var levels: [CGFloat]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeNSView(context: Context) -> PlaybackBarsView { PlaybackBarsView() }
    func updateNSView(_ view: PlaybackBarsView, context: Context) {
        view.configure(playing: playing, reduceMotion: reduceMotion, color: NSColor(tint), levels: levels)
    }
    static func dismantleNSView(_ view: PlaybackBarsView, coordinator: ()) { view.stop() }
}

/// Highlights changes in each live frequency band against its recent level.
/// A steady signal settles; only changes in the audio can raise a bar again.
struct CompactSpectrum {
    static let resting: [CGFloat] = [0.18, 0.28, 0.36, 0.26, 0.18]
    static let silence = [CGFloat](repeating: 0.14, count: 5)
    private var baseline = [CGFloat](repeating: 0, count: 5)

    mutating func scales(playing: Bool, levels: [CGFloat], deltaTime: TimeInterval = 1.0 / 60) -> [CGFloat] {
        guard playing, levels.count >= 72 else {
            baseline = Array(repeating: 0, count: 5)
            return Self.resting
        }
        let dt = deltaTime.isFinite ? min(0.1, max(1.0 / 240, deltaTime)) : 1.0 / 60
        let follow = CGFloat(1 - exp(-dt / 0.65))
        let ranges = [0..<8, 8..<18, 18..<32, 32..<50, 50..<72]
        return ranges.enumerated().map { index, range in
            var peak: CGFloat = 0, sumSquares: CGFloat = 0
            for bin in range {
                let value = levels[bin].isFinite ? min(1, max(0, levels[bin])) : 0
                peak = max(peak, value); sumSquares += value * value
            }
            // Broad-band energy matters more than a single hot FFT bin.
            let energy = peak * 0.25 + sqrt(sumSquares / CGFloat(range.count)) * 0.75
            baseline[index] += (energy - baseline[index]) * follow
            // The absolute signal always supplies a visible body. Only positive
            // transients add lift: a falling beat must never cancel audible audio.
            // Reserve the top quarter for those transients, rather than boosting
            // every sustained band to maximum or subtracting it down to silence.
            let body = pow(energy, 0.65) * 0.72
            let beat = min(0.28, max(0, energy - baseline[index]) * 2.4)
            let response = body + beat
            return 0.14 + 0.84 * response
        }
    }
}

final class PlaybackBarsView: NSView {
    private let bars = (0..<5).map { _ in CALayer() }
    private var lastColor: NSColor?
    private var scales = CompactSpectrum.resting
    private var playing = false
    private var reduceMotion = false
    private var geometrySize = CGSize.zero
    private var geometryScale: CGFloat = 0

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        for bar in bars {
            bar.cornerRadius = 1.1
            bar.backgroundColor = NSColor.white.cgColor
            layer?.addSublayer(bar)
        }
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(playing: Bool, reduceMotion: Bool, color: NSColor, levels: [CGFloat]) {
        if reduceMotion && !self.reduceMotion { stop() }
        self.playing = playing
        self.reduceMotion = reduceMotion
        if lastColor != color {
            let animateColor = lastColor != nil && !reduceMotion && window != nil
            lastColor = color
            for bar in bars {
                let current = bar.presentation()?.backgroundColor ?? bar.backgroundColor
                CATransaction.begin(); CATransaction.setDisableActions(true)
                bar.backgroundColor = color.cgColor
                CATransaction.commit()
                bar.removeAnimation(forKey: "tint")
                if animateColor {
                    let transition = CABasicAnimation(keyPath: "backgroundColor")
                    transition.fromValue = current; transition.toValue = color.cgColor
                    transition.duration = 0.28
                    transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    bar.add(transition, forKey: "tint")
                }
            }
        }
        scales = playing && levels.count == 5 ? levels : CompactSpectrum.resting
        updateHeights(animated: !reduceMotion && window != nil)
    }

    override func layout() {
        super.layout()
        let backingScale = window?.backingScaleFactor ?? 2
        guard geometrySize != bounds.size || geometryScale != backingScale else { return }
        geometrySize = bounds.size; geometryScale = backingScale
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let width: CGFloat = 2.2, gap: CGFloat = 2.0
        let start = (bounds.width - (width * 5 + gap * 4)) / 2
        for (index, bar) in bars.enumerated() {
            bar.removeAnimation(forKey: "level")
            bar.bounds = CGRect(x: 0, y: 0, width: width, height: max(width, min(17, bounds.height) * scales[index]))
            bar.position = CGPoint(x: start + CGFloat(index) * (width + gap) + width / 2, y: bounds.midY)
            bar.contentsScale = backingScale
        }
        CATransaction.commit()
    }

    private func updateHeights(animated: Bool) {
        guard bounds.height > 0 else { return }
        for (index, bar) in bars.enumerated() {
            let height = max(2.2, min(17, bounds.height) * scales[index])
            guard abs(height - bar.bounds.height) > 0.06 else { continue }
            let current = bar.presentation()?.bounds.height ?? bar.bounds.height
            CATransaction.begin(); CATransaction.setDisableActions(true)
            bar.bounds.size.height = height
            CATransaction.commit()
            bar.removeAnimation(forKey: "level")
            if animated {
                // Animate layer height, not a scaled capsule: the end caps stay
                // round. Retarget from the visible height for uninterrupted motion.
                let transition = CABasicAnimation(keyPath: "bounds.size.height")
                transition.fromValue = current; transition.toValue = height
                transition.duration = !playing ? 0.20 : height > current ? 0.04 : 0.075
                transition.timingFunction = CAMediaTimingFunction(name: .easeOut)
                bar.add(transition, forKey: "level")
            }
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stop() }
        needsLayout = true
    }

    func stop() { bars.forEach { $0.removeAllAnimations() } }
}
