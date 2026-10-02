import AppKit
import QuartzCore

/// One display-synchronized clock for the short window transition. Retargeting
/// starts at the displayed frame; no timer or display link remains alive at rest.
@MainActor final class PanelMotion: NSObject {
    enum Curve: Equatable { case easeOut, cellDivision }
    private struct Movement {
        weak var window: NSWindow?
        let from: CGRect
        let to: CGRect
        let start: CFTimeInterval
        let duration: CFTimeInterval
        let fromAlpha: CGFloat
        let toAlpha: CGFloat
        let curve: Curve
        let update: ((CGRect, CGFloat) -> Void)?
        let completion: (() -> Void)?
    }
    private var movements: [ObjectIdentifier: Movement] = [:]
    private var link: AnyObject?
    private var fallbackClock: Timer?

    func move(_ window: NSWindow, to frame: CGRect, duration: TimeInterval, screen: NSScreen, alpha: CGFloat = 1,
              curve: Curve = .easeOut, update: ((CGRect, CGFloat) -> Void)? = nil, completion: (() -> Void)? = nil) {
        let id = ObjectIdentifier(window)
        if duration > 0, let current = movements[id], current.to == frame, current.toAlpha == alpha { return }
        let previous = movements.removeValue(forKey: id)
        previous?.completion?()
        guard duration > 0, window.isVisible else {
            update?(frame, 1); completion?()
            window.setFrame(frame, display: true)
            window.alphaValue = alpha
            stopWhenIdle()
            return
        }
        guard window.frame != frame || window.alphaValue != alpha else { update?(frame, 1); completion?(); stopWhenIdle(); return }
        movements[id] = Movement(window: window, from: window.frame, to: frame, start: CACurrentMediaTime(), duration: duration,
                                 fromAlpha: window.alphaValue, toAlpha: alpha, curve: curve, update: update, completion: completion)
        update?(window.frame, 0)
        if link == nil && fallbackClock == nil {
            if #available(macOS 14, *) {
                let displayLink = screen.displayLink(target: self, selector: #selector(step(_:)))
                displayLink.add(to: .main, forMode: .common)
                link = displayLink
            } else {
                // Ventura has no AppKit CADisplayLink. Keep the same contour
                // and timing, with a common-mode clock only during movement.
                let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.tick() }
                }
                RunLoop.main.add(timer, forMode: .common)
                fallbackClock = timer
            }
        }
    }

    func cancel(_ window: NSWindow) {
        movements.removeValue(forKey: ObjectIdentifier(window))?.completion?()
        stopWhenIdle()
    }

    @available(macOS 14, *)
    @objc private func step(_ link: CADisplayLink) { tick() }

    private func tick() {
        let now = CACurrentMediaTime()
        for (id, movement) in movements {
            guard let window = movement.window else { movements[id] = nil; movement.completion?(); continue }
            let t = min(1, max(0, (now - movement.start) / movement.duration))
            let progress = movement.curve == .cellDivision ? t * t * (3 - 2 * t) : 1 - pow(1 - t, 3)
            let from = movement.from, to = movement.to
            // Open a little space for the narrowing neck. Bounding this by
            // travel distance keeps both entrance and return monotonic.
            let lead = movement.curve == .cellDivision ? min(8, abs(to.minX - from.minX) * 0.2) * sin(.pi * progress) : 0
            let frame = CGRect(x: from.minX + (to.minX - from.minX) * progress + lead,
                               y: from.minY + (to.minY - from.minY) * progress,
                               width: from.width + (to.width - from.width) * progress,
                               height: from.height + (to.height - from.height) * progress)
            window.setFrame(t == 1 ? to : frame, display: true)
            let contentProgress: CGFloat
            if movement.curve == .cellDivision {
                // Text fades away before merging and arrives after division.
                let phase = movement.toAlpha < movement.fromAlpha ? progress / 0.32 : (progress - 0.64) / 0.30
                let bounded = min(1, max(0, phase))
                contentProgress = bounded * bounded * (3 - 2 * bounded)
            } else { contentProgress = progress }
            window.alphaValue = movement.fromAlpha + (movement.toAlpha - movement.fromAlpha) * contentProgress
            movement.update?(frame, progress)
            if t == 1 { movements[id] = nil; movement.completion?() }
        }
        stopWhenIdle()
    }

    private func stopWhenIdle() {
        if movements.isEmpty {
            if #available(macOS 14, *) { (link as? CADisplayLink)?.invalidate() }
            link = nil
            fallbackClock?.invalidate(); fallbackClock = nil
        }
    }

}
