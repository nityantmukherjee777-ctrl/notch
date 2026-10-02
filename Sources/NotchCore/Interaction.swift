import Foundation

public enum SwipeDirection: Equatable { case left, right, up, down }

/// One navigation action per physical trackpad gesture. Momentum never switches again.
public struct SwipeAccumulator {
    private var x: Double = 0, y: Double = 0
    private var fired = false
    public init() {}
    public mutating func consume(dx: Double, dy: Double, precise: Bool, began: Bool, ended: Bool, momentum: Bool) -> SwipeDirection? {
        guard precise, !momentum else { return nil }
        if began { x = 0; y = 0; fired = false }
        defer { if ended { x = 0; y = 0; fired = false } }
        guard !fired else { return nil }
        x += dx; y += dy
        if abs(x) > 55 && abs(x) > abs(y) * 1.4 { fired = true; return x < 0 ? .left : .right }
        if abs(y) > 55 && abs(y) > abs(x) * 1.4 { fired = true; return y < 0 ? .up : .down }
        return nil
    }
}

public struct LyricLine: Identifiable, Equatable {
    public var id: Int
    public var time: TimeInterval
    public var text: String
}
public enum LyricsParser {
    public static func parse(_ text: String) -> [LyricLine] {
        let pattern = #"\[(\d+):(\d{2}(?:\.\d+)?)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        var rows: [(Double, String)] = []
        for row in text.components(separatedBy: .newlines) {
            let raw = row as NSString
            let matches = regex.matches(in: row, range: NSRange(location: 0, length: raw.length))
            guard let last = matches.last else { continue }
            let words = raw.substring(from: NSMaxRange(last.range)).trimmingCharacters(in: .whitespaces)
            for match in matches {
                guard let minutes = Double(raw.substring(with: match.range(at: 1))), let seconds = Double(raw.substring(with: match.range(at: 2))), seconds < 60 else { continue }
                let time = minutes * 60 + seconds
                guard time.isFinite, time >= 0, time <= 31_536_000 else { continue }
                rows.append((time, words))
            }
        }
        return rows.sorted { $0.0 < $1.0 }.enumerated().map { LyricLine(id: $0.offset, time: $0.element.0, text: $0.element.1) }
    }
}

public enum HardwareControl: Int {
    case volumeUp = 0, volumeDown = 1, brightnessUp = 2, brightnessDown = 3, mute = 7
    public func adjusted(_ value: Double, step: Double) -> Double {
        let direction = self == .volumeDown || self == .brightnessDown ? -1.0 : 1.0
        return min(1, max(0, value + direction * step))
    }
}
