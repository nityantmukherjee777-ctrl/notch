import CoreAudio
import Testing
@testable import Notch

private final class FakeAudioStream: AudioCaptureStream {
    var stops = 0
    func stop() { stops += 1 }
}

@MainActor private final class CaptureFixture {
    var streams: [FakeAudioStream] = []
    var analyzers: [SpectrumAnalyzer] = []
    var changes: [() -> Void] = []
    var attempts = 0
    var failures: [AudioTapError] = []
    var now: TimeInterval = 100
    private let suite: String
    let defaults: UserDefaults
    init() {
        suite = "notch.audio.recovery.\(UUID())"
        defaults = UserDefaults(suiteName: suite)!
    }
    deinit { defaults.removePersistentDomain(forName: suite) }

    func service() -> AudioVisualizerService {
        AudioVisualizerService(defaults: defaults, factory: { receiver, changed in
            self.attempts += 1
            if !self.failures.isEmpty { throw self.failures.removeFirst() }
            let stream = FakeAudioStream()
            self.streams.append(stream); self.analyzers.append(SpectrumAnalyzer(count: 72, deliver: receiver)); self.changes.append(changed)
            return stream
        }, dispose: { $0.stop() }, clock: { self.now }, recoveryDelay: { _ in .milliseconds(1) }, monitorHealth: false)
    }

    func sendFrame(index: Int = 0, amplitude: Float = 0.4) {
        var samples = (0..<4096).map { amplitude * sin(Float($0) * 2 * .pi * 1000 / 48000) }
        let format = AudioStreamBasicDescription(mSampleRate: 48000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
            mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0)
        samples.withUnsafeMutableBytes { bytes in
            var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 1,
                mDataByteSize: UInt32(bytes.count), mData: bytes.baseAddress))
            analyzers[index].process(bufferList: &list, format: format)
        }
    }
}

@MainActor struct AudioVisualizerRecoveryTests {
    private func settle(_ milliseconds: Int = 40) async {
        try? await Task.sleep(for: .milliseconds(milliseconds))
    }

    @Test func unsupportedAudioNeverStartsOrRetriesCapture() async {
        let fixture = CaptureFixture()
        fixture.defaults.set(true, forKey: "audioVisualizerNeedsRetry")
        var attempts = 0
        let service = AudioVisualizerService(defaults: fixture.defaults, factory: { _, _ in
            attempts += 1
            return FakeAudioStream()
        }, captureSupported: false, dispose: { $0.stop() }, monitorHealth: false)
        service.setActive(true); service.setCompactActive(true)
        service.retry(); service.suspend(); service.recover(); service.checkHealth()
        await settle(390)
        #expect(attempts == 0 && !service.isSupported && !service.needsRetry)
        #expect(service.error?.contains("14.2") == true)
        #expect(service.levels.allSatisfy { $0 == 0 })
        // An old permission latch remains available if this Mac is upgraded.
        #expect(fixture.defaults.bool(forKey: "audioVisualizerNeedsRetry"))
        service.stop()
    }

    @Test func temporaryDeviceFailureRecoversWithoutPermissionLatch() async {
        let fixture = CaptureFixture()
        fixture.failures = [.coreAudio(operation: "start audio tap", status: kAudioHardwareNotReadyError)]
        let service = fixture.service()
        service.setCompactActive(true)
        await settle()
        #expect(fixture.attempts == 2)
        fixture.sendFrame(); await settle()
        #expect(service.levels.max()! > 0.5)
        #expect(!service.needsRetry && service.error == nil)
        #expect(!fixture.defaults.bool(forKey: "audioVisualizerNeedsRetry"))
        service.stop()
        #expect(fixture.streams.allSatisfy { $0.stops == 1 })
    }

    @Test func permissionDenialNeverAutomaticallyReprompts() async {
        let fixture = CaptureFixture()
        fixture.failures = [.coreAudio(operation: "create audio tap", status: kAudioDevicePermissionsError)]
        let service = fixture.service()
        service.setCompactActive(true); await settle()
        service.recover(); service.checkHealth()
        service.setActive(true); service.setCompactActive(false)
        await settle()
        #expect(fixture.attempts == 1 && service.needsRetry)
        #expect(fixture.service().needsRetry)
        service.retry(); await settle()
        #expect(fixture.attempts == 2 && !service.needsRetry)
        service.stop()
    }

    @Test func legacyFailureRequiresExplicitRetry() async {
        let fixture = CaptureFixture()
        fixture.defaults.set(true, forKey: "audioVisualizerNeedsRetry")
        let service = fixture.service()
        service.setActive(true); service.recover(); await settle()
        #expect(fixture.attempts == 0)
        service.retry(); await settle()
        #expect(fixture.attempts == 1)
        service.stop()
    }

    @Test func wakePreservesHoveredScrubberAndRejectsOldFrames() async {
        let fixture = CaptureFixture(), service: AudioVisualizerService
        service = fixture.service()
        service.setActive(true); await settle()
        fixture.sendFrame(); await settle()
        service.recover(); await settle(390)
        #expect(fixture.attempts == 2 && fixture.streams[0].stops == 1)
        fixture.sendFrame(index: 0); await settle()
        #expect(service.levels.allSatisfy { $0 == 0 })
        fixture.sendFrame(index: 1); await settle()
        #expect(service.levels.max()! > 0.5)
        service.stop()
    }

    @Test func sleepSuspendsCaptureWithoutLosingDemand() async {
        let fixture = CaptureFixture(), service: AudioVisualizerService
        service = fixture.service()
        service.setActive(true); await settle()
        service.suspend()
        service.setCompactActive(true); await settle(390)
        #expect(fixture.attempts == 1 && fixture.streams[0].stops == 1)
        service.recover(); await settle(390)
        #expect(fixture.attempts == 2)
        service.stop()
    }

    @Test func routingChangesAreCoalescedAndOldListenersIgnored() async {
        let fixture = CaptureFixture(), service: AudioVisualizerService
        service = fixture.service()
        service.setCompactActive(true); await settle()
        fixture.changes[0](); fixture.changes[0](); fixture.changes[0]()
        await settle(390)
        #expect(fixture.attempts == 2)
        fixture.changes[0](); await settle(390)
        #expect(fixture.attempts == 2)
        fixture.sendFrame(index: 1); await settle()
        #expect(service.levels.max()! > 0.5)
        service.stop()
    }

    @Test func silenceIsHealthyButMissingCallbacksRecover() async {
        let fixture = CaptureFixture(), service: AudioVisualizerService
        service = fixture.service()
        service.setActive(true); await settle()
        fixture.now += 10
        fixture.sendFrame(amplitude: 0); await settle()
        service.checkHealth(); await settle()
        #expect(fixture.attempts == 1 && service.levels.allSatisfy { $0 == 0 })
        fixture.now += 4
        service.checkHealth(); await settle()
        #expect(fixture.attempts == 2 && fixture.streams[0].stops == 1)
        service.stop()
    }

    @Test func disablingCancelsRecoveryAndSharedDemandKeepsStream() async {
        let fixture = CaptureFixture(), service: AudioVisualizerService
        service = fixture.service()
        service.setActive(true); service.setCompactActive(true); await settle()
        service.setActive(false); await settle(450)
        #expect(fixture.streams[0].stops == 0 && fixture.attempts == 1)
        service.recover(); service.setCompactActive(false); await settle(450)
        #expect(fixture.attempts == 1 && fixture.streams[0].stops == 1)
        service.stop()
    }

    @Test func lateStartIsDisposedAfterStop() async {
        let stream = FakeAudioStream()
        var continuation: CheckedContinuation<AudioCaptureStream, Error>?
        let service = AudioVisualizerService(defaults: CaptureFixture().defaults,
            factory: { _, _ in try await withCheckedThrowingContinuation { continuation = $0 } },
            dispose: { $0.stop() }, monitorHealth: false)
        service.setActive(true); await settle()
        service.stop()
        continuation?.resume(returning: stream); await settle()
        #expect(stream.stops == 1 && service.levels.allSatisfy { $0 == 0 })
    }

    @Test func persistentDeviceFailureHasBoundedRetries() async {
        let fixture = CaptureFixture()
        fixture.failures = Array(repeating: .coreAudio(operation: "start audio tap", status: kAudioHardwareNotRunningError), count: 10)
        let service = fixture.service()
        service.setActive(true); await settle(200)
        #expect(fixture.attempts == 7 && service.needsRetry)
        #expect(!fixture.defaults.bool(forKey: "audioVisualizerNeedsRetry"))
        await settle()
        #expect(fixture.attempts == 7)
        service.stop()
    }
}
