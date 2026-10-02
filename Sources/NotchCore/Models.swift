import Foundation
import CoreGraphics

public enum ActivityID: String, Codable, CaseIterable, Identifiable {
    case music, timer, codex, power
    public var id: String { rawValue }
    public var title: String {
        switch self { case .music: return "Music"; case .timer: return "Timer"; case .codex: return "Codex"; case .power: return "Keep Awake" }
    }
    public var symbol: String {
        switch self { case .music: return "music.note"; case .timer: return "timer"; case .codex: return "sparkle"; case .power: return "cup.and.saucer.fill" }
    }
}

public struct LiveActivity: Identifiable, Equatable {
    public var id: ActivityID
    public var provider: String
    public var title: String
    public var detail: String
    public var isActive: Bool
    public var actions: [String]
    public init(id: ActivityID, provider: String, title: String, detail: String, isActive: Bool, actions: [String]) {
        self.id = id; self.provider = provider; self.title = title; self.detail = detail; self.isActive = isActive; self.actions = actions
    }
}

public struct Preferences: Codable, Equatable {
    public var musicEnabled = true
    public var timerEnabled = true
    public var powerEnabled = true
    public var batteryEnabled = true
    public var bluetoothAlertsEnabled: Bool? = true
    public var volumeEnabled = true
    public var brightnessEnabled: Bool? = true
    public var hudEnabled: Bool? = true
    public var replaceSystemHUD: Bool? = true
    public var codexEnabled = false
    public var hoverEnabled = true
    public var hoverDelay = 0.3
    public var selectedDisplay: UInt32 = 0
    public var primary: ActivityID? = nil
    public var favorites: [ActivityID] = [.music, .timer, .power, .codex]
    public var compactScale = 1.0
    public var accent = "neutral"
    public var shortcutKey = "N"
    public var shortcutEnabled = true
    public var completionSound = true
    public var codexPath = ""
    public init() {}

    public mutating func sanitize() {
        hoverDelay = hoverDelay.isFinite ? min(0.8, max(0.15, hoverDelay)) : 0.3
        compactScale = compactScale.isFinite ? min(1.2, max(0.85, compactScale)) : 1
        var seen = Set<ActivityID>()
        favorites = favorites.filter { seen.insert($0).inserted }
        if !["N", "K", "J", "Space"].contains(shortcutKey) { shortcutKey = "N" }
    }
}

public struct Countdown: Codable, Equatable {
    public var name: String = "Focus"
    public var duration: TimeInterval = 1500
    public var deadline: Date?
    public var pausedRemaining: TimeInterval?
    public var completed = false
    public init() {}
    public mutating func sanitize(at now: Date) {
        name = String(name.prefix(60))
        duration = duration.isFinite ? min(86_400, max(1, duration)) : 1500
        if let deadline {
            let interval = deadline.timeIntervalSince(now)
            self.deadline = interval.isFinite ? min(deadline, now.addingTimeInterval(duration)) : nil
            pausedRemaining = nil
        } else if let remaining = pausedRemaining {
            pausedRemaining = remaining.isFinite ? min(duration, max(0, remaining)) : nil
        }
        if completed { deadline = nil; pausedRemaining = nil }
    }
    public var isRunning: Bool { deadline != nil }
    public var isPaused: Bool { pausedRemaining != nil }
    public var isActive: Bool { isRunning || isPaused || completed }
    public func remaining(at now: Date) -> TimeInterval {
        if let deadline { return max(0, deadline.timeIntervalSince(now)) }
        return pausedRemaining ?? (completed ? 0 : duration)
    }
    public mutating func start(name: String, seconds: TimeInterval, now: Date) {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Timer" : String(name.prefix(60))
        duration = min(86400, max(1, seconds.isFinite ? seconds : 1500))
        deadline = now.addingTimeInterval(duration); pausedRemaining = nil; completed = false
    }
    public mutating func pause(at now: Date) {
        guard isRunning else { return }
        if reconcile(at: now) { return }
        pausedRemaining = remaining(at: now); deadline = nil
    }
    public mutating func resume(at now: Date) {
        guard let remaining = pausedRemaining else { return }
        deadline = now.addingTimeInterval(remaining); pausedRemaining = nil
    }
    @discardableResult public mutating func reconcile(at now: Date) -> Bool {
        guard let deadline, deadline <= now else { return false }
        self.deadline = nil; pausedRemaining = nil; completed = true; return true
    }
    public mutating func reset() { deadline = nil; pausedRemaining = nil; completed = false }
}

public struct QuotaWindow: Codable, Equatable {
    public let usedPercent: Double
    public let windowDurationMins: Int?
    public let resetsAt: Double?
    public var remainingPercent: Int { Int((100 - min(100, max(0, usedPercent))).rounded()) }
    public var resetDate: Date? { resetsAt.map { Date(timeIntervalSince1970: $0) } }
    public var label: String {
        guard let minutes = windowDurationMins else { return "Usage window" }
        if minutes % 1440 == 0 { return "\(minutes / 1440)-day window" }
        if minutes % 60 == 0 { return "\(minutes / 60)-hour window" }
        return "\(minutes)-minute window"
    }
    public init(usedPercent: Double, windowDurationMins: Int?, resetsAt: Double?) {
        self.usedPercent = usedPercent; self.windowDurationMins = windowDurationMins; self.resetsAt = resetsAt
    }
}

public struct QuotaSnapshot: Equatable {
    public let primary: QuotaWindow?
    public let secondary: QuotaWindow?
    public let fetchedAt: Date
    public init(primary: QuotaWindow?, secondary: QuotaWindow?, fetchedAt: Date) {
        self.primary = primary; self.secondary = secondary; self.fetchedAt = fetchedAt
    }
    public func isStale(at now: Date) -> Bool {
        now.timeIntervalSince(fetchedAt) > 180 || [primary?.resetDate, secondary?.resetDate].compactMap { $0 }.contains { $0 <= now }
    }
    public static func parse(_ object: [String: Any], at now: Date) -> QuotaSnapshot? {
        // A present multi-bucket response is authoritative; never substitute a different quota.
        let bucket: [String: Any]?
        if let buckets = object["rateLimitsByLimitId"] as? [String: Any] {
            bucket = buckets["codex"] as? [String: Any]
        } else if let legacy = object["rateLimits"] as? [String: Any],
                  legacy["limitId"] == nil || legacy["limitId"] as? String == "codex" {
            bucket = legacy
        } else { bucket = nil }
        guard let bucket else { return nil }
        func window(_ key: String) -> QuotaWindow? {
            guard let raw = bucket[key] as? [String: Any],
                  let percent = raw["usedPercent"] as? NSNumber,
                  CFGetTypeID(percent) != CFBooleanGetTypeID(), percent.doubleValue.isFinite else { return nil }
            func number(_ key: String) -> Double? {
                guard let value = raw[key] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else { return nil }
                return value.doubleValue
            }
            let duration = number("windowDurationMins").flatMap { $0 > 0 && $0 < Double(Int.max) && $0.rounded() == $0 ? Int($0) : nil }
            return QuotaWindow(usedPercent: percent.doubleValue,
                               windowDurationMins: duration,
                               resetsAt: number("resetsAt").flatMap { $0 >= 0 && $0 <= 253_402_300_799 ? $0 : nil })
        }
        let primary = window("primary"), secondary = window("secondary")
        guard primary != nil || secondary != nil else { return nil }
        return QuotaSnapshot(primary: primary, secondary: secondary, fetchedAt: now)
    }
}

import CoreFoundation

public enum ActivityLayout {
    public static func primary(pinned: ActivityID?, musicPlaying: Bool, timerActive: Bool, codexEnabled: Bool) -> ActivityID? {
        if let pinned {
            switch pinned {
            case .music: if musicPlaying { return .music }
            case .timer: if timerActive { return .timer }
            case .codex: if codexEnabled { return .codex }
            case .power: break
            }
        }
        if musicPlaying { return .music }
        if timerActive { return .timer }
        return nil
    }
    public static func satellites(primary: ActivityID?, timerActive: Bool, codexEnabled: Bool, musicActive: Bool = false) -> [ActivityID] {
        var result: [ActivityID] = []
        if timerActive && primary != .timer { result.append(.timer) }
        if codexEnabled && primary != .codex { result.append(.codex) }
        if musicActive && primary != .music { result.append(.music) }
        return result
    }
    public static func fitsSatellites(availableWidth: Double, count: Int, bubbleWidth: Double = 28) -> Bool {
        availableWidth >= Double(count) * (bubbleWidth + 4)
    }
}

/// Geometry shared by the native windows and regression checks.
public enum NotchGeometry {
    /// Screen-space hit target for the lone control on the lyrics page. The
    /// visible 28-point button remains in its original location and styling.
    public static func lyricsBackHitFrame(panel: CGRect, safeTop: CGFloat) -> CGRect {
        let contentWidth = expandedSize(availableWidth: panel.width - 32, safeTop: safeTop, lyrics: true).width
        let controlLeft = panel.minX + (panel.width - contentWidth) / 2 + 24
        let toolbarHeight = max(safeTop, 28) + 8
        return CGRect(x: controlLeft - 8, y: panel.maxY - toolbarHeight,
                      width: 44, height: toolbarHeight)
    }
    public static func expandedSize(availableWidth: CGFloat, safeTop: CGFloat, lyrics: Bool = false) -> CGSize {
        if lyrics {
            return CGSize(width: min(820, availableWidth), height: max(safeTop, 24) + 408)
        }
        return CGSize(width: min(560, availableWidth), height: max(safeTop, 24) + 202)
    }
    public static func compactHeight(safeTop: CGFloat) -> CGFloat { safeTop > 0 ? safeTop : 36 }
    public static func bubbleDiameter(compactHeight: CGFloat) -> CGFloat { min(32, max(24, compactHeight - 4)) }
    public static func bubbleFrame(nextTo main: CGRect, compactHeight: CGFloat, index: Int) -> CGRect {
        let diameter = bubbleDiameter(compactHeight: compactHeight)
        let gap: CGFloat = 4
        let x: CGFloat = main.maxX + gap + CGFloat(index) * (diameter + gap)
        let y: CGFloat = main.maxY - (compactHeight + diameter) / 2
        return CGRect(x: x, y: y, width: diameter, height: diameter)
    }
}

public func clockString(_ seconds: TimeInterval) -> String {
    let value = Int(ceil(min(31_536_000, max(0, seconds.isFinite ? seconds : 0))))
    return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) : String(format: "%02d:%02d", value / 60, value % 60)
}
