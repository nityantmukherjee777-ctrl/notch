import AppKit

/// Short-lived click-through silhouette. Both lobes and the pinched waist live
/// in one window, so a new circle genuinely grows out of the notch surface.
@MainActor final class BubbleDivision {
    private let window: NSPanel
    private let surface: DivisionSurface

    init(source: CGRect, destination: CGRect) {
        let canvas = source.union(destination).insetBy(dx: -20, dy: -12)
        window = NSPanel(contentRect: canvas, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = false
        window.level = .statusBar; window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .canJoinAllApplications, .ignoresCycle]
        window.ignoresMouseEvents = true; window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        surface = DivisionSurface(frame: CGRect(origin: .zero, size: canvas.size))
        surface.origin = canvas.origin
        surface.parent = source.offsetBy(dx: -canvas.minX, dy: -canvas.minY)
        window.contentView = surface
        // Keep every existing activity's content above the temporary membrane.
        window.orderBack(nil)
    }

    func update(frame: CGRect, progress: CGFloat) {
        surface.child = frame.offsetBy(dx: -surface.origin.x, dy: -surface.origin.y)
        surface.progress = max(0, min(1, progress))
        surface.needsDisplay = true
    }
    func finish() { window.orderOut(nil) }
}

@MainActor final class DivisionSurface: NSView {
    var origin = CGPoint.zero
    var parent = CGRect.zero
    var child = CGRect.zero
    var progress: CGFloat = 0
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        Self.contour(parent: parent, child: child, progress: progress).fill()
    }

    /// The zero contour of a smooth union of two circle distance fields. The
    /// neck narrows continuously, even at the instant it separates into two
    /// contours. There are no phase-dependent shape swaps or pointed joins.
    static func contour(parent: CGRect, child: CGRect, progress: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        let radius = child.height / 2
        guard radius > 0, radius.isFinite, progress.isFinite else { return path }
        let p = min(1, max(0, progress))
        let parentRadius = radius * (1 - smooth((p - 0.68) / 0.32))
        let childRadius = radius * (0.35 + 0.65 * smooth(p / 0.60))
        let blend = radius * 1.8 * smooth(p / 0.20) * (1 - smooth((p - 0.55) / 0.30))
        let left = min(parent.midX - parentRadius, child.midX - childRadius) - blend / 4
        let right = max(parent.midX + parentRadius, child.midX + childRadius) + blend / 4
        let maxHeight = max(parentRadius, childRadius) + blend / 4 + 1
        let middleY = child.midY

        func distance(_ x: CGFloat, _ y: CGFloat) -> CGFloat {
            let a = hypot(x - parent.midX, y) - parentRadius
            let b = hypot(x - child.midX, y) - childRadius
            guard blend > 0.0001 else { return min(a, b) }
            let h = max(blend - abs(a - b), 0) / blend
            return min(a, b) - h * h * blend / 4
        }
        var upper: [CGPoint] = []
        var lower: [CGPoint] = []
        func closeContour() {
            guard let first = upper.first else { return }
            path.move(to: first)
            for point in upper.dropFirst() { path.line(to: point) }
            for point in lower.reversed() { path.line(to: point) }
            path.close()
            upper.removeAll(keepingCapacity: true)
            lower.removeAll(keepingCapacity: true)
        }
        // Only a tiny transient surface is sampled; the display link and this
        // work stop completely once the 540ms animation finishes.
        let steps = max(1, Int(ceil((right - left) / 0.35)))
        for index in 0...steps {
            let x = left + (right - left) * CGFloat(index) / CGFloat(steps)
            guard distance(x, 0) <= 0 else { closeContour(); continue }
            var low: CGFloat = 0, high = maxHeight
            for _ in 0..<11 {
                let midpoint = (low + high) / 2
                if distance(x, midpoint) <= 0 { low = midpoint } else { high = midpoint }
            }
            upper.append(CGPoint(x: x, y: middleY + low))
            lower.append(CGPoint(x: x, y: middleY - low))
        }
        closeContour()
        return path
    }

    private static func smooth(_ t: CGFloat) -> CGFloat {
        let v = max(0, min(1, t)); return v * v * (3 - 2 * v)
    }
}
