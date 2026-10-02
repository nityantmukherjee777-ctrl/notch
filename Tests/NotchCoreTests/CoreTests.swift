import Testing
import Foundation
import CoreGraphics
@testable import NotchCore

struct CoreTests {
    let start = Date(timeIntervalSince1970: 1_000_000)
    @Test func testTimerSurvivesRelaunchAndSleep() throws {
        var timer = Countdown()
        timer.start(name: "Build", seconds: 60, now: start)
        let encoded = try JSONEncoder().encode(timer)
        var restored = try JSONDecoder().decode(Countdown.self, from: encoded)
        #expect(restored.remaining(at: start.addingTimeInterval(20)) == 40)
        let didComplete = restored.reconcile(at: start.addingTimeInterval(90))
        #expect(didComplete)
        #expect(restored.completed)
        let completedAgain = restored.reconcile(at: start.addingTimeInterval(100))
        #expect(!completedAgain)
    }
    @Test func testPausedTimerDoesNotElapseWhileAppIsClosed() throws {
        var timer = Countdown(); timer.start(name: "", seconds: 100, now: start)
        timer.pause(at: start.addingTimeInterval(30))
        #expect(timer.name == "Timer")
        #expect(timer.remaining(at: start.addingTimeInterval(900)) == 70)
        timer.resume(at: start.addingTimeInterval(900))
        #expect(timer.remaining(at: start.addingTimeInterval(930)) == 40)
        timer.reset(); #expect(!(timer.isActive))
    }
    @Test func testPauseAfterDeadlineFinishesInsteadOfCreatingZeroTimer() {
        var timer = Countdown(); timer.start(name: "Test", seconds: 1, now: start)
        timer.pause(at: start.addingTimeInterval(2))
        #expect(timer.completed); #expect(!(timer.isPaused))
    }
    @Test func testQuotaBucketsAndClamping() {
        let data: [String: Any] = ["rateLimitsByLimitId": ["codex": ["primary": ["usedPercent": 25.4, "windowDurationMins": 300, "resetsAt": start.timeIntervalSince1970 + 100]]]]
        let result = QuotaSnapshot.parse(data, at: start)
        #expect(result?.primary?.remainingPercent == 75)
        #expect(result?.primary?.label == "5-hour window")
        #expect(!(result!.isStale(at: start.addingTimeInterval(50))))
        #expect(result!.isStale(at: start.addingTimeInterval(101)))
        #expect(QuotaWindow(usedPercent: 120, windowDurationMins: 300, resetsAt: nil).remainingPercent == 0)
        #expect(QuotaWindow(usedPercent: -5, windowDurationMins: 300, resetsAt: nil).remainingPercent == 100)
    }
    @Test func testMissingUsageIsNotZero() {
        #expect((QuotaSnapshot.parse(["rateLimits": ["primary": ["windowDurationMins": 300]]], at: start)) == nil)
        #expect((QuotaSnapshot.parse(["rateLimits": NSNull()], at: start)) == nil)
        #expect((QuotaSnapshot.parse(["rateLimits": ["primary": ["usedPercent": true]]], at: start)) == nil)
        #expect((QuotaSnapshot.parse(["rateLimitsByLimitId": ["other": ["primary": ["usedPercent": 5]]], "rateLimits": ["primary": ["usedPercent": 1]]], at: start)) == nil)
    }
    @Test func testLegacyAndSecondaryOnlyQuota() {
        let result = QuotaSnapshot.parse(["rateLimits": ["limitId": "codex", "secondary": ["usedPercent": 90, "windowDurationMins": 10080]]], at: start)
        #expect((result?.primary) == nil); #expect(result?.secondary?.remainingPercent == 10)
        #expect(result!.isStale(at: start.addingTimeInterval(181)))
    }
    @Test func testMusicTimerAndCodexRemainIndependent() {
        let main = ActivityLayout.primary(pinned: nil, musicPlaying: true, timerActive: true, codexEnabled: true)
        #expect(main == .music)
        #expect(ActivityLayout.satellites(primary: main, timerActive: true, codexEnabled: true) == [.timer, .codex])
        #expect(ActivityLayout.satellites(primary: main, timerActive: true, codexEnabled: false) == [.timer])
        #expect(ActivityLayout.primary(pinned: .timer, musicPlaying: true, timerActive: true, codexEnabled: true) == .timer)
        #expect(ActivityLayout.satellites(primary: .timer, timerActive: true, codexEnabled: true, musicActive: true) == [.codex, .music])
        #expect(ActivityLayout.primary(pinned: .codex, musicPlaying: true, timerActive: true, codexEnabled: false) == .music)
    }
    @Test func testOverflowThreshold() {
        #expect(!(ActivityLayout.fitsSatellites(availableWidth: 63, count: 2)))
        #expect(ActivityLayout.fitsSatellites(availableWidth: 64, count: 2))
        #expect(ActivityLayout.fitsSatellites(availableWidth: 0, count: 0))
    }
    @Test func circularBubblesStayBesideTheNotchWhenItExpands() {
        let compact = CGRect(x: 585, y: 950, width: 300, height: 32)
        let expanded = CGRect(x: 505, y: 632, width: 460, height: 350)
        let first = NotchGeometry.bubbleFrame(nextTo: compact, compactHeight: 32, index: 0)
        let second = NotchGeometry.bubbleFrame(nextTo: compact, compactHeight: 32, index: 1)
        let opened = NotchGeometry.bubbleFrame(nextTo: expanded, compactHeight: 32, index: 0)
        #expect(first.width == first.height && first.width == 28)
        #expect(first.minX - compact.maxX == 4)
        #expect(second.minX - first.maxX == 4)
        #expect(opened.minY == first.minY)
        #expect(opened.minX - expanded.maxX == 4)
        #expect(NotchGeometry.compactHeight(safeTop: 32) == 32)
        #expect(NotchGeometry.compactHeight(safeTop: 0) == 36)
    }
    @Test func testPreferencesAndLongTimerFormatting() throws {
        var preferences = Preferences(); preferences.codexEnabled = true; preferences.primary = .music
        #expect(try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences)) == preferences)
        #expect(clockString(3661) == "1:01:01")
        #expect(clockString(-3) == "00:00")
    }
    @Test func lyricsBackHitTargetTracksThePanelAndStaysInTheToolbar() {
        let panel = CGRect(x: 305, y: 516, width: 860, height: 440)
        let hit = NotchGeometry.lyricsBackHitFrame(panel: panel, safeTop: 32)
        #expect(hit.contains(CGPoint(x: 363, y: 934)))
        #expect(!hit.contains(CGPoint(x: 420, y: 934)))
        #expect(!hit.contains(CGPoint(x: 363, y: 900)))
        let shifted = panel.offsetBy(dx: 320, dy: -200)
        #expect(NotchGeometry.lyricsBackHitFrame(panel: shifted, safeTop: 32).contains(CGPoint(x: 683, y: 734)))
    }
}

@Suite struct InteractionTests {
    @Test func swipesFireOnceAndIgnoreMomentum() {
        var swipe = SwipeAccumulator()
        #expect(swipe.consume(dx: -20, dy: 2, precise: true, began: true, ended: false, momentum: false) == nil)
        #expect(swipe.consume(dx: -40, dy: 1, precise: true, began: false, ended: false, momentum: false) == .left)
        #expect(swipe.consume(dx: -90, dy: 1, precise: true, began: false, ended: true, momentum: false) == nil)
        #expect(swipe.consume(dx: -90, dy: 0, precise: true, began: false, ended: false, momentum: true) == nil)
        #expect(swipe.consume(dx: 1, dy: 60, precise: true, began: true, ended: true, momentum: false) == .down)
        #expect(swipe.consume(dx: 60, dy: 0, precise: false, began: true, ended: true, momentum: false) == nil)
    }
    @Test func ambiguousDiagonalDoesNotChangeWidget() {
        var swipe = SwipeAccumulator()
        #expect(swipe.consume(dx: 70, dy: 70, precise: true, began: true, ended: false, momentum: false) == nil)
        #expect(swipe.consume(dx: 60, dy: 0, precise: true, began: false, ended: true, momentum: false) == .right)
    }
    @Test func lyricsHandleMultipleTimestampsAndMetadata() {
        let rows = LyricsParser.parse("[ar:Test]\n[00:12.50][01:03.125]Test line\n[00:02.00]Intro\n[00:99]Invalid\nplain text")
        #expect(rows.map(\.time) == [2, 12.5, 63.125])
        #expect(Set(rows.map(\.id)).count == 3)
        #expect(rows[1].text == "Test line")
        #expect(LyricsParser.parse("No timed lyrics").isEmpty)
    }
}

@Suite struct PolishTests {
    @Test func regularPagesAreCompactAndLyricsUsesTheLargeGeometry() {
        let size = NotchGeometry.expandedSize(availableWidth: 1000, safeTop: 32)
        #expect(size.width == 560 && size.height == 234)
        let narrow = NotchGeometry.expandedSize(availableWidth: 500, safeTop: 32)
        #expect(narrow.width == 500 && narrow.height == size.height)
        let lyrics = NotchGeometry.expandedSize(availableWidth: 1000, safeTop: 32, lyrics: true)
        #expect(lyrics.width == 820 && lyrics.height == 440)
    }
    @Test func hardwareKeysAreLimitedAndClamped() {
        #expect(HardwareControl(rawValue: 16) == nil)
        #expect(HardwareControl.volumeUp.adjusted(0.99, step: 1.0 / 16) == 1)
        #expect(HardwareControl.brightnessDown.adjusted(0.01, step: 1.0 / 16) == 0)
        #expect(HardwareControl.volumeUp.adjusted(0.5, step: 1.0 / 64) == 0.515625)
    }
    @Test func newHUDPreferencesPreserveOldSettings() throws {
        let data = try JSONEncoder().encode(Preferences())
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "replaceSystemHUD")
        object.removeValue(forKey: "brightnessEnabled")
        object["codexEnabled"] = true
        let restored = try JSONDecoder().decode(Preferences.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(restored.codexEnabled)
        #expect(restored.replaceSystemHUD != false)
    }
}
