import Foundation
import Testing
import IOKit.pwr_mgt
import NotchCore
@testable import Notch

@Suite(.serialized) @MainActor struct ServiceTests {
    private func fixture(mode: String) throws -> URL {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("notch-protocol-\(UUID().uuidString).py")
        let script = """
        #!/usr/bin/python3
        import sys, json, time
        mode = '\(mode)'
        for line in sys.stdin:
            request = json.loads(line)
            method = request.get('method')
            if method == 'initialize':
                print(json.dumps({'id': 1, 'result': {'userAgent': 'fixture'}}), flush=True)
            elif method == 'account/rateLimits/read':
                if mode == 'offline':
                    sys.exit(1)
                if mode == 'timeout':
                    time.sleep(30)
                    continue
                reply = {'id': request['id']}
                if mode == 'auth':
                    reply['error'] = {'code': -32000, 'message': 'Unauthorized: sign in'}
                elif mode == 'missing':
                    reply['result'] = {'rateLimits': {'primary': {'resetsAt': time.time() + 3600}}}
                else:
                    reply['result'] = {'rateLimits': {'primary': {'usedPercent': 25, 'windowDurationMins': 300, 'resetsAt': time.time() + 3600}}}
                print(json.dumps(reply), flush=True)
                if mode == 'updates':
                    print(json.dumps({'method': 'account/rateLimits/updated', 'params': {'rateLimits': {'primary': {'usedPercent': 43, 'windowDurationMins': 300, 'resetsAt': time.time() + 3600}}}}), flush=True)
        """
        try script.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        return file
    }
    private func waitUntil(_ predicate: () -> Bool) async throws {
        for _ in 0..<100 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(predicate(), "Service did not reach its expected state in five seconds")
    }
    @Test func usageUpdatesAndDisableReenable() async throws {
        let file = try fixture(mode: "updates")
        defer { try? FileManager.default.removeItem(at: file) }
        let service = CodexService()
        defer { service.stop() }
        service.configure(enabled: true, path: file.path)
        try await waitUntil { service.snapshot?.primary?.remainingPercent == 57 }
        #expect(service.connected)
        service.configure(enabled: false, path: file.path)
        #expect(service.snapshot == nil)
        #expect(!service.connected && !service.fetching)
        service.refresh()
        try await Task.sleep(for: .milliseconds(100))
        #expect(service.status == "Tracking is off")
        service.configure(enabled: true, path: file.path)
        try await waitUntil { service.snapshot?.primary?.remainingPercent == 57 }
    }
    @Test func authenticationFailureAndMissingFields() async throws {
        for mode in ["auth", "missing"] {
            let file = try fixture(mode: mode)
            defer { try? FileManager.default.removeItem(at: file) }
            let service = CodexService()
            service.configure(enabled: true, path: file.path)
            try await waitUntil { !service.fetching && service.lastError != nil }
            #expect(service.snapshot == nil)
            #expect(service.status == (mode == "auth" ? "Sign in to Codex" : "Quota not provided"))
            service.stop()
        }
    }
    @Test func offlineAndDisableDuringRequest() async throws {
        for mode in ["offline", "timeout"] {
            let file = try fixture(mode: mode)
            defer { try? FileManager.default.removeItem(at: file) }
            let service = CodexService()
            service.configure(enabled: true, path: file.path)
            if mode == "offline" {
                try await waitUntil { service.lastError != nil }
                #expect(!service.connected)
            } else {
                try await waitUntil { service.connected }
                #expect(service.fetching)
            }
            service.stop()
            try await Task.sleep(for: .milliseconds(150))
            #expect(service.status == "Tracking is off")
            #expect(service.snapshot == nil && !service.fetching)
        }
    }
    @Test func persistedTimerDeadlineAndPause() throws {
        let suite = "notch-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = TimerService(defaults: defaults)
        first.start(name: "Restored", minutes: 5)
        let restored = TimerService(defaults: defaults)
        #expect(restored.countdown.deadline == first.countdown.deadline)
        restored.togglePause()
        let paused = TimerService(defaults: defaults)
        #expect(paused.countdown.isPaused)
        #expect(paused.remaining > 295 && paused.remaining <= 300)
        first.reset(); restored.reset(); paused.reset()
    }
    @Test func expiredTimerRestoresCompletion() throws {
        let suite = "notch-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var countdown = Countdown()
        countdown.start(name: "While asleep", seconds: 60, now: Date().addingTimeInterval(-120))
        defaults.set(try JSONEncoder().encode(countdown), forKey: "countdown")
        let service = TimerService(defaults: defaults)
        #expect(service.countdown.completed && service.remaining == 0)
        service.reset()
    }
    @Test func keepAwakeReleasesOnDisableAndExpiredWake() async throws {
        func ownedAssertions() -> Int {
            var raw: Unmanaged<CFDictionary>?
            guard IOPMCopyAssertionsByProcess(&raw) == kIOReturnSuccess,
                  let dictionary = raw?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return 0 }
            return dictionary[NSNumber(value: ProcessInfo.processInfo.processIdentifier), default: []].filter {
                $0[kIOPMAssertionNameKey as String] as? String == "Notch Keep Awake"
            }.count
        }
        let service = PowerService()
        defer { service.stop() }
        #expect(!service.isAwake)
        service.start(minutes: 1)
        #expect(service.isAwake && service.until != nil)
        try await waitUntil { ownedAssertions() == 1 }
        service.wake(at: Date().addingTimeInterval(120))
        #expect(!service.isAwake && service.until == nil)
        try await waitUntil { ownedAssertions() == 0 }
        service.start(minutes: 0)
        #expect(service.isAwake && service.until == nil)
        service.stop()
        try await waitUntil { ownedAssertions() == 0 }
        #expect(!PowerService().isAwake)
    }
}

@Suite @MainActor struct MediaServiceTests {
    @Test func multipleSourcesCanSwitchWithoutStoppingPlayback() {
        let service = MusicService()
        let spotify = Track(source: .spotify, title: "Test track", artist: "Test", album: "", duration: 200, position: 20, playing: true, artworkURL: "")
        service.applyDesktopTracks([.spotify: spotify])
        service.receiveSystem(["title": "Test video", "bundleIdentifier": "com.google.Chrome", "playing": true, "durationMicros": 120_000_000, "elapsedTimeMicros": 15_000_000])
        #expect(service.availableTracks.count == 2)
        #expect(service.track?.source == .system)
        service.cycleSource(1)
        #expect(service.track?.source == .spotify)
        let allPlaying = service.availableTracks.allSatisfy { $0.playing }
        #expect(allPlaying)
        service.cycleSource(-1)
        #expect(service.track?.source == .system)
        service.receiveSystem(nil)
        #expect(service.availableTracks.count == 1)
        #expect(service.track?.source == .spotify)
    }
    @Test func invalidSystemMediaDoesNotBecomeAStaleSession() {
        let service = MusicService()
        service.receiveSystem(["title": "Video", "bundleIdentifier": "com.brave.Browser", "playing": false])
        #expect(service.track?.playing == false)
        #expect(service.track?.duration == 0)
        service.receiveSystem(["title": NSNull(), "bundleIdentifier": "com.brave.Browser"])
        #expect(service.track == nil && service.availableTracks.isEmpty)
        service.receiveSystem(["title": "Video", "bundleIdentifier": "", "playing": true])
        #expect(service.availableTracks.isEmpty)
    }
    @Test func spotifyRemainsAvailableWhenDesktopScriptingHasNoTrack() {
        let service = MusicService()
        service.receiveSystem(["title": "Song", "artist": "Artist", "bundleIdentifier": "com.spotify.client", "playing": true,
                               "durationMicros": 200_000_000, "elapsedTimeMicros": 15_000_000])
        service.applyDesktopTracks([:])
        #expect(service.track?.source == .spotify)
        #expect(service.track?.remoteBundleID == "com.spotify.client")
        #expect(service.track?.playing == true)
        #expect(service.track?.duration == 200)
        #expect((service.track?.position ?? 0) >= 15)
        #expect(service.availableTracks.count == 1)
        service.receiveSystem(nil)
        #expect(service.track == nil && service.availableTracks.isEmpty)
    }
    @Test func desktopAndSystemSpotifyAreOneSourceWithDesktopPreferred() {
        let service = MusicService()
        let spotify = Track(source: .spotify, title: "Song", artist: "Artist", album: "Album", duration: 200, position: 25, playing: true, artworkURL: "")
        service.applyDesktopTracks([.spotify: spotify])
        service.receiveSystem(["title": "Song", "bundleIdentifier": "com.spotify.client", "playing": true])
        #expect(service.availableTracks == [spotify])
        #expect(service.track == spotify)
        service.applyDesktopTracks([:])
        #expect(service.track?.source == .spotify && service.track?.remoteBundleID != nil)
        service.applyDesktopTracks([.spotify: spotify])
        #expect(service.track == spotify)
    }
    @Test func playingSystemSpotifyReplacesPausedDesktopResponse() {
        let service = MusicService()
        let paused = Track(source: .spotify, title: "Song", artist: "Artist", album: "", duration: 200, position: 25, playing: false, artworkURL: "")
        service.applyDesktopTracks([.spotify: paused])
        service.receiveSystem(["title": "Song", "bundleIdentifier": "com.spotify.client", "playing": true])
        #expect(service.track?.playing == true && service.availableTracks.count == 1)
        #expect(service.track?.remoteBundleID == "com.spotify.client")
        service.receiveSystem(["title": "Song", "bundleIdentifier": "com.spotify.client", "playing": false])
        #expect(service.track == paused)
    }
    @Test func appleMusicFallbackKeepsIdentityAndCoexistsWithSpotify() {
        let service = MusicService()
        let spotify = Track(source: .spotify, title: "Song", artist: "Artist", album: "", duration: 200, position: 25, playing: true, artworkURL: "")
        service.applyDesktopTracks([.spotify: spotify])
        service.receiveSystem(["title": "Other song", "bundleIdentifier": "com.apple.Music", "playing": true])
        #expect(service.track?.source == .appleMusic)
        #expect(service.availableTracks.count == 2)
        service.cycleSource(-1)
        #expect(service.track == spotify)
    }
}
