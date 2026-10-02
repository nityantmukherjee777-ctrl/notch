import Foundation
import Testing
import NotchCore

@Suite struct CodexActivityTests {
    private func reading(_ used: Double, at seconds: Double, reset: Double = 5000) -> QuotaSnapshot {
        QuotaSnapshot(primary: QuotaWindow(usedPercent: used, windowDurationMins: 300, resetsAt: reset), secondary: nil, fetchedAt: Date(timeIntervalSince1970: seconds))
    }
    @Test func onlyConsumptionExtendsTheFiveMinuteWindow() {
        var activity = CodexActivity()
        activity.observe(reading(20, at: 100))
        #expect(!activity.isVisible(at: Date(timeIntervalSince1970: 100), providerRunning: true))
        activity.observe(reading(21, at: 110))
        #expect(activity.isVisible(at: Date(timeIntervalSince1970: 110), providerRunning: true))
        activity.observe(reading(21, at: 400))
        #expect(activity.isVisible(at: Date(timeIntervalSince1970: 409), providerRunning: true))
        #expect(!activity.isVisible(at: Date(timeIntervalSince1970: 410), providerRunning: true))
        #expect(!activity.isVisible(at: Date(timeIntervalSince1970: 111), providerRunning: false))
        activity.observe(reading(22, at: 411))
        #expect(activity.isVisible(at: Date(timeIntervalSince1970: 411), providerRunning: true))
    }
    @Test func resetsAndOutOfOrderReadsAreNotFalseActivity() {
        var activity = CodexActivity()
        activity.observe(reading(90, at: 4900))
        activity.observe(reading(0, at: 5001, reset: 10000))
        #expect(activity.lastConsumption == nil)
        activity.observe(reading(95, at: 4950))
        activity.observe(reading(1, at: 5020, reset: 10000))
        #expect(activity.lastConsumption == Date(timeIntervalSince1970: 5020))
        #expect(!activity.isVisible(at: Date(timeIntervalSince1970: 6020), providerRunning: true))
    }
    @Test func executableDiscoverySurvivesOldPathsAndHonorsCustomChoice() {
        let newPath = "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex"
        let paths = ["/old/codex", newPath]
        #expect(CodexExecutable.firstAvailable(custom: "/missing", bundled: paths, executable: { $0 == newPath }) == newPath)
        #expect(CodexExecutable.firstAvailable(custom: "/custom", bundled: paths, executable: { $0 == newPath || $0 == "/custom" }) == "/custom")
        #expect(CodexExecutable.firstAvailable(custom: "", bundled: [], executable: { _ in false }) == nil)
    }
}
