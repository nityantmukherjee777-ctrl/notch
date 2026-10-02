import Foundation

/// Quota is account-wide and coarse; a successful poll is not consumption.
/// Keep only numeric quota metadata, never conversations or credentials.
public struct CodexActivity {
    public static let inactivityInterval: TimeInterval = 5 * 60
    public private(set) var lastConsumption: Date?
    private var baseline: QuotaSnapshot?
    public init() {}

    public mutating func observe(_ snapshot: QuotaSnapshot) {
        if let baseline, snapshot.fetchedAt < baseline.fetchedAt { return }
        defer { baseline = snapshot }
        guard let previous = baseline else { return }
        let pairs = [(previous.primary, snapshot.primary), (previous.secondary, snapshot.secondary)]
        if pairs.contains(where: { old, new in
            guard let old, let new, new.usedPercent.isFinite else { return false }
            if old.resetsAt == new.resetsAt && old.windowDurationMins == new.windowDurationMins {
                return new.usedPercent > old.usedPercent
            }
            // A new window with usage is activity; a reset to zero isn't.
            return old.resetDate.map { $0 > previous.fetchedAt && $0 <= snapshot.fetchedAt } == true && new.usedPercent > 0
        }) { recordConsumption(at: snapshot.fetchedAt) }
    }

    public mutating func recordConsumption(at date: Date) {
        if lastConsumption == nil || date > lastConsumption! { lastConsumption = date }
    }

    public func isVisible(at now: Date, providerRunning: Bool) -> Bool {
        guard providerRunning, let lastConsumption else { return false }
        return (0..<Self.inactivityInterval).contains(now.timeIntervalSince(lastConsumption))
    }
}

public enum CodexExecutable {
    public static func firstAvailable(custom: String, bundled: [String],
                                      executable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> String? {
        ([custom] + bundled + ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"])
            .first { !$0.isEmpty && executable($0) }
    }
}
