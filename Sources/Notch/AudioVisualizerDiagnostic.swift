import AppKit
import Combine

/// Opt-in local release check. Outputs counts only; never saves audio, modifies
/// privacy grants, or clears the explicit-retry latch. Uses the real signed app.
@MainActor final class AudioVisualizerDiagnostic {
    private let service = AudioVisualizerService()
    private var subscription: AnyCancellable?
    private var peak = CGFloat.zero
    private var beforeRecovery = 0

    func start() {
        subscription = service.$levels.dropFirst().sink { [weak self] levels in
            self?.peak = max(self?.peak ?? 0, levels.max() ?? 0)
        }
        service.setCompactActive(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self else { return }
            self.beforeRecovery = self.service.receivedFrames
            self.service.recover()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 9) { [weak self] in
            guard let self else { return }
            let after = self.service.receivedFrames - self.beforeRecovery
            let report: [String: Any] = ["framesBeforeRecovery": self.beforeRecovery,
                "framesAfterRecovery": after, "peak": Double(self.peak),
                "needsRetry": self.service.needsRetry, "error": self.service.error ?? ""]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
               let text = String(data: data, encoding: .utf8) { print(text) }
            self.service.stop()
            // Allow the worker to destroy the aggregate and tap before exit.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                exit(self.beforeRecovery > 0 && after > 0 ? 0 : 1)
            }
        }
    }
}
