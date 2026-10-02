import SwiftUI

struct PremiumSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var tint: Color = .white
    var label: String
    var hoverVisualizer = false
    var controlHeight: CGFloat = 20
    var visualizerLevels: [CGFloat] = []
    var onHoverChanged: (Bool) -> Void = { _ in }
    var onEditingChanged: (Bool) -> Void = { _ in }
    @State private var hovered = false
    @State private var dragging = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fraction: Double {
        guard range.upperBound > range.lowerBound else { return 0 }
        return min(1, max(0, (value - range.lowerBound) / (range.upperBound - range.lowerBound)))
    }

    var body: some View {
        GeometryReader { proxy in
            let width = max(1, proxy.size.width)
            ZStack {
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.12))
                        .overlay { Capsule().strokeBorder(.white.opacity(0.055), lineWidth: 0.5) }
                        .frame(height: 4)
                    Capsule()
                        .fill(LinearGradient(colors: [tint.opacity(0.72), tint], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(2, width * fraction), height: 4)
                }
                .frame(width: width, height: controlHeight, alignment: controlHeight > 20 ? .bottom : .center)
                .opacity(hoverVisualizer && hovered && !dragging ? 0 : 1)

                if hoverVisualizer {
                    HoverWaveform(progress: fraction, levels: visualizerLevels)
                        .opacity(hovered && !dragging ? 1 : 0)
                }
            }
            .frame(width: width, height: controlHeight, alignment: .center)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { gesture in
                if !dragging { dragging = true; onEditingChanged(true) }
                setValue(at: gesture.location.x, width: width)
            }.onEnded { gesture in
                setValue(at: gesture.location.x, width: width)
                dragging = false
                onEditingChanged(false)
            })
        }
        .frame(height: controlHeight)
        .onHover { value in hovered = value; onHoverChanged(value) }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: dragging)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue("\(Int((fraction * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            let delta = (range.upperBound - range.lowerBound) / 20
            onEditingChanged(true)
            switch direction {
            case .increment: value = min(range.upperBound, value + delta)
            case .decrement: value = max(range.lowerBound, value - delta)
            @unknown default: break
            }
            onEditingChanged(false)
        }
    }

    private func setValue(at x: CGFloat, width: CGFloat) {
        let progress = min(1, max(0, x / width))
        value = range.lowerBound + Double(progress) * (range.upperBound - range.lowerBound)
    }
}

struct HoverWaveform: View {
    var progress: Double
    var levels: [CGFloat]

    var body: some View {
        Canvas { context, size in
            let values = levels.isEmpty ? [CGFloat](repeating: 0, count: 72) : levels
            // Leave clear black gaps between fine, round-ended strokes, even
            // on smaller displays. Both modes share the track's bottom baseline.
            let barCount = max(2, min(112, Int(size.width / 3.4)))
            let stroke: CGFloat = 1.35
            let baseline = size.height - 2

            for index in 0..<barCount {
                let location = CGFloat(index) / CGFloat(barCount - 1)
                let source = location * CGFloat(values.count - 1)
                let lower = min(values.count - 1, Int(source.rounded(.down)))
                let upper = min(values.count - 1, lower + 1)
                let mix = source - CGFloat(lower)
                let level = values[lower] + (values[upper] - values[lower]) * mix
                let shaped = min(1, max(0, level))
                let height = stroke + shaped * max(0, size.height - 4 - stroke)
                let x = stroke / 2 + location * max(0, size.width - stroke)
                let bar = Path(roundedRect: CGRect(x: x - stroke / 2, y: baseline - height + stroke / 2,
                                                  width: stroke, height: height),
                               cornerRadius: stroke / 2)
                let played = Double(location) <= progress
                context.fill(bar, with: .color(.white.opacity(played ? 0.98 : 0.72)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
    }
}
