import AppKit
import SwiftUI
import Carbon
import Combine
import NotchCore

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor final class PanelController {
    let state: AppState
    private let panel: NotchPanel
    private var bubbleWindows: [String: NSPanel] = [:]
    private var bubbleRetirements: [String: Task<Void, Never>] = [:]
    private var bubbleSlots: [String: Int] = [:]
    private var bubbles: [NSPanel] { Array(bubbleWindows.values) }
    private var notice: NSPanel?
    private var host: NSHostingView<NotchRoot>?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var subscriptions: Set<AnyCancellable> = []
    private var hoverTask: Task<Void, Never>?
    private var closeTask: Task<Void, Never>?
    private var interactionTask: Task<Void, Never>?
    private var hoverInside = false
    private var pointerTimer: Timer?
    private var enteredAt: Date?
    private var leftAt: Date?
    private var suppressHoverUntilExit = false
    private var menuTracking = false
    private var lyricsBackPending = false
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var shortcutSignature = ""
    private var displaySignature = ""
    private var lastNotice: String?
    private var dismissOnExit = false
    private var isUpdating = false
    private var layoutSignature = ""
    private let motion = PanelMotion()
    private var activeFrame = CGRect.zero
    private var interactionFrame = CGRect.zero
    private var swipe = SwipeAccumulator()
    private var screen: NSScreen? {
        if state.preferences.selectedDisplay != 0,
           let saved = NSScreen.screens.first(where: { $0.displayID == state.preferences.selectedDisplay }) { return saved }
        return NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens.first
    }
    init(state: AppState) {
        self.state = state
        panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        configure(panel)
        state.onLayoutChange = { [weak self] in self?.layout() }
        state.$preferences.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.layout() } }.store(in: &subscriptions)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown && event.keyCode == 53 && self.state.expanded { self.close(animated: false); return nil }
            if event.type == .scrollWheel, self.activeFrame.contains(NSEvent.mouseLocation) {
                if let direction = self.swipe.consume(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY,
                    precise: event.hasPreciseScrollingDeltas, began: event.phase == .began,
                    ended: event.phase == .ended || event.phase == .cancelled, momentum: !event.momentumPhase.isEmpty) {
                    if !self.state.expanded { self.open() }
                    switch direction {
                    case .left: self.state.cycleWidget(1)
                    case .right: self.state.cycleWidget(-1)
                    case .up: if self.state.selected == .music && !self.state.mediaDetail { self.state.music.cycleSource(1) }
                    case .down: if self.state.selected == .music && !self.state.mediaDetail { self.state.music.cycleSource(-1) }
                    }
                }
                // Lyrics retain native vertical scrolling; horizontal gestures still navigate.
                if !self.state.mediaDetail || abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) { return nil }
            }
            self.handleMouse(event); return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown]) { [weak self] event in self?.handleMouse(event) }
        observers.append(NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.menuTracking = true; self?.hoverTask?.cancel() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.menuTracking = false }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.layout(animated: false) } })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.close(); self?.layout(animated: false) }
        })
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, ref in
            guard let ref else { return OSStatus(eventNotHandledErr) }
            let controller = Unmanaged<PanelController>.fromOpaque(ref).takeUnretainedValue()
            Task { @MainActor in controller.toggleFromKeyboard() }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler)
        layout(animated: false)
        pointerTimer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updatePointer() }
        }
        pointerTimer?.tolerance = 0.02
        if let pointerTimer { RunLoop.main.add(pointerTimer, forMode: .common) }
    }
    private func configure(_ window: NSPanel) {
        window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = false
        window.level = .statusBar; window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .canJoinAllApplications, .ignoresCycle]
        window.isMovable = false; window.animationBehavior = .none
        window.acceptsMouseMovedEvents = true; window.isReleasedWhenClosed = false
    }
    func open(_ activity: ActivityID? = nil, keyboard: Bool = false, focus: Bool = false) {
        hoverTask?.cancel(); closeTask?.cancel(); interactionTask?.cancel()
        if let activity, state.isEnabled(activity) { state.selected = activity }
        else if !state.expanded, let primary = state.primary { state.selected = primary }
        if state.selected == .codex { state.codex.refresh() }
        // Lyrics has its own explicit album-art action. A normal click or
        // keyboard open always uses the stable regular-tool geometry.
        state.mediaDetail = false
        state.presentingExpanded = true
        state.expanded = true
        if state.mediaDetail { state.lyrics.load(state.music.track) }
        dismissOnExit = !keyboard && !focus
        state.music.setExpanded(state.selected == .music)
        layout(animated: !keyboard)
        if keyboard || focus { panel.makeKeyAndOrderFront(nil) }
    }
    func showLyrics() {
        closeTask?.cancel()
        state.selected = .music; state.presentingExpanded = true; state.expanded = true; state.mediaDetail = true
        state.lyrics.load(state.music.track); dismissOnExit = false
        layout(); panel.makeKeyAndOrderFront(nil)
    }
    func backToPlayer() {
        state.mediaDetail = false; state.selected = .music
        dismissOnExit = false; layout()
    }
    func close(animated: Bool = true) {
        hoverTask?.cancel(); closeTask?.cancel(); dismissOnExit = false
        guard state.expanded else { return }
        state.expanded = false
        enteredAt = nil; leftAt = nil; suppressHoverUntilExit = activeFrame.insetBy(dx: -4, dy: -4).contains(NSEvent.mouseLocation)
        state.music.setExpanded(false)
        panel.resignKey(); layout(animated: animated)
        if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            closeTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(210))
                guard !Task.isCancelled, let self, !self.state.expanded else { return }
                self.state.presentingExpanded = false
                self.state.mediaDetail = false
            }
        } else {
            state.presentingExpanded = false
            state.mediaDetail = false
        }
    }
    func toggleFromKeyboard() { state.expanded ? close(animated: false) : open(keyboard: true) }
    private func handleMouse(_ event: NSEvent) {
        let location = NSEvent.mouseLocation
        if event.type == .leftMouseDown, state.expanded, state.mediaDetail, !lyricsBackPending,
           let screen, NotchGeometry.lyricsBackHitFrame(panel: panel.frame, safeTop: screen.safeAreaInsets.top).contains(location) {
            // Some top-edge clicks are routed around the hosting view. Both
            // local and global mouse monitors see the pointer, so handle this
            // one control at the presentation layer before regular dismissal.
            lyricsBackPending = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.state.mediaDetail { self.backToPlayer() }
                self.lyricsBackPending = false
            }
            return
        }
        guard !menuTracking else { return }
        let inMain = interactionFrame.insetBy(dx: -3, dy: -3).contains(location)
        setPointerPassThrough(!inMain)
        let inside = inMain || bubbles.contains { $0.isVisible && $0.frame.insetBy(dx: -4, dy: -4).contains(location) }
        if event.type == .leftMouseDown || event.type == .rightMouseDown {
            if state.expanded && !inside { close() }
            return
        }
        updatePointer()
    }
    private func setPointerPassThrough(_ ignore: Bool) {
        // The lyrics page nearly fills the fixed canvas. Its back button must
        // receive the first click even if the pointer moved into the window
        // without a mouseMoved event (for example after switching Spaces).
        let shouldIgnore = state.expanded && state.mediaDetail ? false : ignore
        // AppKit sends a WindowServer transaction even for identical assignments.
        if panel.ignoresMouseEvents != shouldIgnore { panel.ignoresMouseEvents = shouldIgnore }
    }
    private func updatePointer() {
        guard !menuTracking else { enteredAt = nil; leftAt = nil; return }
        let point = NSEvent.mouseLocation
        let mainInside = interactionFrame.insetBy(dx: -4, dy: -4).contains(point)
        let inside = mainInside || bubbles.contains { $0.isVisible && $0.frame.insetBy(dx: -5, dy: -5).contains(point) }
        setPointerPassThrough(!mainInside)
        hoverInside = inside
        if !inside { suppressHoverUntilExit = false; enteredAt = nil }
        if state.expanded {
            enteredAt = nil
            if inside || !dismissOnExit { leftAt = nil }
            else {
                if leftAt == nil { leftAt = Date() }
                if Date().timeIntervalSince(leftAt!) >= 0.35 { close() }
            }
        } else if mainInside && state.preferences.hoverEnabled && !suppressHoverUntilExit {
            if enteredAt == nil { enteredAt = Date() }
            if Date().timeIntervalSince(enteredAt!) >= state.preferences.hoverDelay {
                enteredAt = nil
                if !frontmostAppCoversDisplay { open() }
            }
        } else { enteredAt = nil }
    }
    // Window bounds and owner IDs are public metadata; no screen capture or Accessibility access.
    // A borderless window covering the screen is treated conservatively as full screen.
    private var frontmostAppCoversDisplay: Bool {
        guard let screen, let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let first = NSScreen.screens.first else { return false }
        let display = CGRect(x: screen.frame.minX, y: first.frame.maxY - screen.frame.maxY, width: screen.frame.width, height: screen.frame.height)
        return windows.contains { window in
            guard window[kCGWindowOwnerPID as String] as? pid_t == front.processIdentifier,
                  window[kCGWindowLayer as String] as? Int == 0,
                  let raw = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: raw) else { return false }
            return bounds.insetBy(dx: -2, dy: -2).contains(display)
        }
    }
    func layout(animated: Bool = true) {
        guard !isUpdating else { return }
        guard let screen else { state.visualizer.setCompactActive(false); return }
        isUpdating = true; defer { isUpdating = false }
        state.visualizer.setCompactActive(state.preferences.musicEnabled && !state.expanded && state.hud == nil && state.bluetooth.announcement == nil &&
            state.music.track?.playing == true && (state.primary == .music || state.satellites.contains(.music)))
        let safe = screen.safeAreaInsets.top
        let notchWidth: CGFloat
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea, safe > 0 { notchWidth = max(120, right.minX - left.maxX) }
        else { notchWidth = 140 }
        let contentWidth = state.primary != nil || state.bluetooth.announcement != nil ? notchWidth + 114 * state.preferences.compactScale : notchWidth + (safe == 0 ? 16 : 0)
        let lyrics = state.expanded && state.selected == .music && state.mediaDetail
        let expandedSize = NotchGeometry.expandedSize(availableWidth: screen.frame.width - 96, safeTop: safe, lyrics: lyrics)
        let expandedWidth = expandedSize.width
        let canvasWidth = min(860.0, screen.frame.width - 64)
        let canvasHeight = min(440.0, screen.frame.height - 80)
        let width: CGFloat = state.expanded ? expandedWidth : state.hud != nil ? notchWidth + 230 : state.bluetooth.announcement != nil ? contentWidth : contentWidth + (state.power.isAwake ? 60 : 0)
        let compactHeight = NotchGeometry.compactHeight(safeTop: safe)
        let height: CGFloat = state.expanded ? expandedSize.height : compactHeight
        let topInset: CGFloat = safe > 0 ? 0 : max(0, screen.frame.maxY - screen.visibleFrame.maxY) + 8
        let target = NSRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - height - topInset, width: width, height: height)
        let metrics = "\(safe):\(notchWidth):\(canvasWidth)"
        let signature = "\(target):\(screen.frame):\(metrics):\(state.satellites):\(state.expanded):\(state.mediaDetail):\(state.transientMessage ?? ""):\(state.bluetooth.announcement?.id.uuidString ?? ""):\(state.preferences.shortcutEnabled):\(state.preferences.shortcutKey)"
        guard signature != layoutSignature else { return }
        layoutSignature = signature
        if host == nil || displaySignature != metrics {
            displaySignature = metrics
            let root = NotchRoot(state: state, safeTop: safe, notchWidth: notchWidth, expandedWidth: canvasWidth,
                open: { [weak self] id, focus in self?.open(id, focus: focus) }, showLyrics: { [weak self] in self?.showLyrics() }, back: { [weak self] in self?.backToPlayer() }, close: { [weak self] in self?.close() })
            if let host { host.rootView = root } else {
                let view = NSHostingView(rootView: root); view.sizingOptions = []; host = view; panel.contentView = view
            }
        }
        let previousFrame = activeFrame
        activeFrame = target
        interactionTask?.cancel()
        if animated && previousFrame != .zero {
            interactionFrame = previousFrame.union(target)
            interactionTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(self?.state.expanded == true ? 290 : 210))
                guard !Task.isCancelled, let self else { return }
                self.interactionFrame = self.activeFrame
                self.setPointerPassThrough(!self.interactionFrame.insetBy(dx: -3, dy: -3).contains(NSEvent.mouseLocation))
            }
        } else {
            interactionFrame = target
        }
        let canvas = NSRect(x: screen.frame.midX - canvasWidth / 2, y: screen.frame.maxY - canvasHeight - topInset, width: canvasWidth, height: canvasHeight)
        if panel.frame != canvas { panel.setFrame(canvas, display: true) }
        let animation: Animation? = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? .smooth(duration: state.expanded ? 0.28 : 0.20, extraBounce: 0) : nil
        withAnimation(animation) { state.surfaceSize = target.size }
        setPointerPassThrough(!interactionFrame.insetBy(dx: -3, dy: -3).contains(NSEvent.mouseLocation))
        panel.orderFrontRegardless()
        updateBubbles(mainFrame: target, screen: screen, safe: safe, animated: animated)
        updateNotice(screen: screen, safe: safe)
        registerShortcut()
    }
    private func move(_ window: NSWindow, to frame: NSRect, animated: Bool) {
        guard let screen else { return }
        let duration = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? (state.expanded ? 0.25 : 0.18) : 0
        motion.move(window, to: frame, duration: duration, screen: screen)
    }
    private func updateBubbles(mainFrame: NSRect, screen: NSScreen, safe: CGFloat, animated: Bool) {
        let activities = state.satellites
        let compactHeight = NotchGeometry.compactHeight(safeTop: safe)
        let diameter = NotchGeometry.bubbleDiameter(compactHeight: compactHeight)
        let available = screen.frame.maxX - mainFrame.maxX - 8
        let overflow = !ActivityLayout.fitsSatellites(availableWidth: available, count: activities.count, bubbleWidth: diameter)
        let items: [ActivityID?] = overflow && !activities.isEmpty ? [nil] : activities.map { Optional($0) }
        let keys = Set(items.map { $0?.rawValue ?? "overflow" })
        let animate = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        for (key, bubble) in bubbleWindows where !keys.contains(key) && bubbleRetirements[key] == nil {
            bubble.ignoresMouseEvents = true
            let slot = bubbleSlots[key] ?? 0
            let source = divisionSource(for: slot, mainFrame: mainFrame, compactHeight: compactHeight, safeTop: safe, surviving: keys)
            if animate {
                let division = BubbleDivision(source: source, destination: bubble.frame)
                motion.move(bubble, to: source, duration: 0.50, screen: screen, alpha: 0, curve: .cellDivision,
                            update: { frame, progress in division.update(frame: frame, progress: 1 - progress) },
                            completion: { division.finish() })
            } else {
                motion.move(bubble, to: source, duration: 0, screen: screen, alpha: 0)
                bubble.orderOut(nil); bubbleWindows[key] = nil; bubbleSlots[key] = nil
                continue
            }
            bubbleRetirements[key] = Task { [weak self, weak bubble] in
                try? await Task.sleep(for: .milliseconds(530))
                guard !Task.isCancelled, let self, let bubble else { return }
                self.motion.cancel(bubble); bubble.orderOut(nil)
                self.bubbleWindows[key] = nil; self.bubbleRetirements[key] = nil; self.bubbleSlots[key] = nil
            }
        }
        for (index, item) in items.enumerated() {
            let key = item?.rawValue ?? "overflow"
            let retirement = bubbleRetirements.removeValue(forKey: key)
            retirement?.cancel()
            let wasRetiring = retirement != nil
            let frame = NotchGeometry.bubbleFrame(nextTo: mainFrame, compactHeight: compactHeight, index: index)
            let entering = bubbleWindows[key] == nil
            bubbleSlots[key] = index
            let bubble: NSPanel
            if let existing = bubbleWindows[key] { bubble = existing }
            else {
                bubble = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                configure(bubble)
                bubble.title = item.map { "\($0.title) activity" } ?? "More activities"
                bubble.setFrame(NSRect(x: mainFrame.maxX - diameter - 10, y: frame.minY, width: diameter, height: diameter), display: false)
                bubble.alphaValue = animate ? 0 : 1
                bubbleWindows[key] = bubble
            }
            // Keep panel identity stable when another activity appears or retires.
            let root = BubbleView(state: state, activity: item, overflow: activities) { [weak self] id in self?.open(id, focus: true) }
            if let view = bubble.contentView as? NSHostingView<BubbleView> { view.rootView = root }
            else { let view = NSHostingView(rootView: root); view.sizingOptions = []; bubble.contentView = view }
            bubble.ignoresMouseEvents = false
            bubble.orderFrontRegardless()
            if animate && (entering || wasRetiring) {
                let source = divisionSource(for: index, mainFrame: mainFrame, compactHeight: compactHeight, safeTop: safe, surviving: keys)
                if entering { bubble.setFrame(source, display: false) }
                let division = BubbleDivision(source: source, destination: frame)
                motion.move(bubble, to: frame, duration: 0.54, screen: screen, curve: .cellDivision,
                            update: { frame, progress in division.update(frame: frame, progress: progress) },
                            completion: { division.finish() })
            } else {
                motion.move(bubble, to: frame, duration: animate ? 0.32 : 0, screen: screen)
            }
        }
    }

    /// Divide from the adjoining live cell. If it has retired, use the notch
    /// itself so a new activity never emerges from an empty screen position.
    private func divisionSource(for index: Int, mainFrame: CGRect, compactHeight: CGFloat, safeTop: CGFloat, surviving: Set<String>) -> CGRect {
        let diameter = NotchGeometry.bubbleDiameter(compactHeight: compactHeight)
        if index > 0,
           let neighbor = bubbleSlots.first(where: { $0.value == index - 1 && surviving.contains($0.key) }),
           let window = bubbleWindows[neighbor.key] {
            return window.frame
        }
        let shoulderInset: CGFloat = safeTop > 0 ? min(12, mainFrame.height * 0.24) : 0
        return CGRect(x: mainFrame.maxX - diameter - shoulderInset, y: mainFrame.maxY - (compactHeight + diameter) / 2,
                      width: diameter, height: diameter)
    }

    private func updateNotice(screen: NSScreen, safe: CGFloat) {
        let signature = "\(state.expanded):\(state.transientMessage ?? "")"
        guard lastNotice != signature else { return }
        lastNotice = signature
        notice?.orderOut(nil); notice = nil
        guard let message = state.transientMessage, !state.expanded else { return }
        let window = NSPanel(contentRect: NSRect(x: screen.frame.midX - 120, y: screen.frame.maxY - max(safe, 30) - 58, width: 240, height: 34), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        configure(window); window.ignoresMouseEvents = true
        window.contentView = NSHostingView(rootView: Text(message).font(.system(size: 11, weight: .medium)).foregroundStyle(.white).frame(maxWidth: .infinity, maxHeight: .infinity).background(.black, in: Capsule()))
        window.orderFrontRegardless(); notice = window
    }
    private func registerShortcut() {
        let signature = "\(state.preferences.shortcutEnabled):\(state.preferences.shortcutKey)"
        guard signature != shortcutSignature else { return }
        shortcutSignature = signature
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        state.shortcutError = nil
        guard state.preferences.shortcutEnabled else { return }
        let codes: [String: UInt32] = ["N": UInt32(kVK_ANSI_N), "K": UInt32(kVK_ANSI_K), "J": UInt32(kVK_ANSI_J), "Space": UInt32(kVK_Space)]
        let code = codes[state.preferences.shortcutKey] ?? UInt32(kVK_ANSI_N)
        let id = EventHotKeyID(signature: 0x4E544348, id: 1)
        if RegisterEventHotKey(code, UInt32(cmdKey | optionKey), id, GetApplicationEventTarget(), 0, &hotKey) != noErr {
            state.shortcutError = "That shortcut is already in use. Choose another key."
        }
    }
}

extension NSScreen {
    var displayID: UInt32 { (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0 }
}
