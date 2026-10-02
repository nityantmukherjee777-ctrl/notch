import Testing
import Foundation
import AppKit
@testable import NotchCore
@testable import Notch

private final class OversizedResponse: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        // No Content-Length: the receiving limit must still apply.
        client?.urlProtocol(self, didLoad: Data(repeating: 42, count: 128))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite @MainActor struct SecurityTests {
    @Test func untrustedNumbersCannotOverflowUIOrSeek() {
        #expect(clockString(Double.greatestFiniteMagnitude) == "8760:00:00")
        #expect(clockString(.infinity) == "00:00")
        let service = MusicService()
        service.receiveSystem(["title": "Malformed", "bundleIdentifier": "test.media", "durationMicros": 1e300, "elapsedTimeMicros": Double.infinity])
        #expect(service.track?.duration == 31_536_000)
        #expect(service.track?.position == 0)
        let parsed = QuotaSnapshot.parse(["rateLimits": ["primary": ["usedPercent": 1, "resetsAt": 1e300]]], at: Date())
        #expect(parsed?.primary?.resetsAt == nil)
        #expect(LyricsParser.parse("[" + String(repeating: "9", count: 400) + ":01]Invalid").isEmpty)
    }
    @Test func corruptSettingsAndTimerAreBounded() {
        var preferences = Preferences()
        preferences.favorites = [.music, .music, .timer]; preferences.hoverDelay = .nan; preferences.compactScale = 1e300
        preferences.sanitize()
        #expect(preferences.favorites == [.music, .timer])
        #expect(preferences.hoverDelay == 0.3 && preferences.compactScale == 1.2)
        var timer = Countdown()
        let now = Date()
        timer.duration = 1e300; timer.deadline = now.addingTimeInterval(1e300); timer.pausedRemaining = 1e300
        timer.sanitize(at: now)
        #expect(timer.duration == 86_400 && timer.remaining(at: now) <= 86_400)
        #expect(timer.pausedRemaining == nil)
    }
    @Test func downloadPolicyRejectsUnsafeDestinations() {
        let hosts: Set<String> = ["i.scdn.co"]
        for value in ["http://i.scdn.co/a", "file:///etc/passwd", "https://localhost/a", "https://i.scdn.co.evil.test/a", "https://user:pass@i.scdn.co/a", "https://i.scdn.co:8443/a"] {
            #expect(!BoundedDownload.allows(URL(string: value)!, hosts: hosts))
        }
        #expect(BoundedDownload.allows(URL(string: "https://i.scdn.co/image/test")!, hosts: hosts))
        #expect(SafeArtwork.image(Data(repeating: 0, count: 100)) == nil)
    }
    @Test func responseLimitAppliesWithoutContentLength() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OversizedResponse.self]
        do {
            _ = try await BoundedDownload.fetch(URLRequest(url: URL(string: "https://fixture.test/image")!), limit: 64, hosts: ["fixture.test"], configuration: config)
            #expect(false, "Oversized response was accepted")
        } catch BoundedDownload.Failure.tooLarge {} // Expected; no actual network request.
    }
}
