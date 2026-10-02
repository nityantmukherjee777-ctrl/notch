import Accelerate
import CoreAudio
import SwiftUI

protocol AudioCaptureStream: AnyObject {
    func stop()
}

enum AudioTapError: Error {
    case coreAudio(operation: String, status: OSStatus)
    case missingFormat
    case unsupportedOS

    var permissionDenied: Bool {
        if case let .coreAudio(_, status) = self {
            return status == kAudioDevicePermissionsError || status == -54
        }
        return false
    }
    var creatingTap: Bool {
        if case let .coreAudio(operation, _) = self { return operation == "create audio tap" }
        return false
    }
}

/// Samples system output only while a visible visualizer needs it. Temporary
/// routing failures recover; permission failures require an explicit retry.
@MainActor final class AudioVisualizerService: ObservableObject {
    typealias CaptureFactory = (@escaping ([CGFloat]) -> Void, @escaping () -> Void) async throws -> AudioCaptureStream
    @Published private(set) var levels = AudioVisualizerService.restingLevels
    private(set) var compactLevels = CompactSpectrum.silence
    private var compactSpectrum = CompactSpectrum()
    private var lastSpectrumTime: TimeInterval?
    private(set) var receivedFrames = 0
    @Published private(set) var error: String?
    @Published private(set) var needsRetry: Bool
    let isSupported: Bool

    private static let barCount = 72
    private static let restingLevels = [CGFloat](repeating: 0, count: barCount)
    private var tap: AudioCaptureStream?
    private var starting = false
    private var suspended = false
    private var compactRequested = false
    private var scrubberRequested = false
    private var requested: Bool { compactRequested || scrubberRequested }
    private var stopTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?
    private var healthTimer: Timer?
    private var startedAt: TimeInterval?
    private var consecutiveFailures = 0
    private var generation = UUID()
    private let defaults: UserDefaults
    private let factory: CaptureFactory
    private let dispose: (AudioCaptureStream) -> Void
    private let clock: () -> TimeInterval
    private let recoveryDelay: (Int) -> Duration
    private let monitorHealth: Bool
    private static let retryKey = "audioVisualizerNeedsRetry"
    private static let capturedKey = "audioVisualizerHasCaptured"

    init(defaults: UserDefaults = .standard,
         factory: CaptureFactory? = nil,
         captureSupported: Bool? = nil,
         dispose: @escaping (AudioCaptureStream) -> Void = AudioCaptureWorker.stop,
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         recoveryDelay: @escaping (Int) -> Duration = { .seconds(min(30, pow(2, Double($0 - 1)))) },
         monitorHealth: Bool = true) {
        self.defaults = defaults
        self.factory = factory ?? AudioCaptureWorker.start
        self.dispose = dispose
        self.clock = clock
        self.recoveryDelay = recoveryDelay
        self.monitorHealth = monitorHealth
        if let captureSupported { isSupported = captureSupported }
        else if #available(macOS 14.2, *) { isSupported = true }
        else { isSupported = factory != nil }
        needsRetry = isSupported && defaults.bool(forKey: Self.retryKey)
        if !isSupported { error = "Beat-synced visualizers require macOS 14.2 or later. Music controls still work." }
        else if needsRetry { error = "Check System Audio Recording Only, then choose Retry visualizer." }
    }

    deinit {
        stopTask?.cancel(); recoveryTask?.cancel(); healthTimer?.invalidate()
        if let tap { dispose(tap) }
    }

    func retry() {
        guard isSupported else { return }
        invalidateCapture()
        consecutiveFailures = 0
        needsRetry = false
        defaults.removeObject(forKey: Self.retryKey)
        error = nil
        updateDemand()
    }

    /// Wake and session recovery preserve an already-hovered scrubber's demand.
    func recover() {
        suspended = false
        guard isSupported, requested, !needsRetry else { return }
        scheduleRecovery(delay: .milliseconds(350), countFailure: false)
    }

    func suspend() {
        suspended = true
        invalidateCapture()
    }

    func openAudioSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    private func makeReceiver(epoch: UUID) -> ([CGFloat]) -> Void {
        { [weak self] levels in
            Task { @MainActor in
                guard let self, self.requested, self.generation == epoch else { return }
                let now = self.clock()
                let interval = self.lastSpectrumTime.map { now - $0 } ?? (1.0 / 60)
                self.lastSpectrumTime = now
                self.receivedFrames += 1
                self.consecutiveFailures = 0
                if !self.defaults.bool(forKey: Self.capturedKey) { self.defaults.set(true, forKey: Self.capturedKey) }
                self.compactLevels = self.compactSpectrum.scales(playing: true, levels: levels, deltaTime: interval)
                self.levels = levels
                if self.error != nil { self.error = nil }
            }
        }
    }

    func setActive(_ active: Bool) {
        guard scrubberRequested != active else { return }
        scrubberRequested = active
        updateDemand()
    }

    func setCompactActive(_ active: Bool) {
        guard compactRequested != active else { return }
        compactRequested = active
        updateDemand()
    }

    private func updateDemand() {
        guard isSupported else { return }
        stopTask?.cancel(); stopTask = nil
        if requested {
            guard tap == nil, !starting, !suspended, recoveryTask == nil, !needsRetry else { return }
            start()
        } else {
            // Never let a queued retry reopen capture after its view disappears.
            recoveryTask?.cancel(); recoveryTask = nil
            stopTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(420))
                guard !Task.isCancelled, let self, !self.requested else { return }
                self.invalidateCapture()
                self.consecutiveFailures = 0
            }
        }
    }

    func stop() {
        compactRequested = false; scrubberRequested = false
        stopTask?.cancel(); stopTask = nil
        invalidateCapture()
        consecutiveFailures = 0
    }

    private func start() {
        starting = true
        let epoch = UUID()
        generation = epoch
        let receiver = makeReceiver(epoch: epoch)
        let factory = factory, dispose = dispose
        Task { [weak self] in
            do {
                let stream = try await factory(receiver) { [weak self] in
                    Task { @MainActor in
                        guard let self, self.generation == epoch else { return }
                        self.recover()
                    }
                }
                guard let self, self.generation == epoch, self.requested else {
                    dispose(stream); return
                }
                self.tap = stream
                self.starting = false
                self.startedAt = self.clock()
                self.error = nil
                self.beginHealthMonitoring()
            } catch {
                guard let self, self.generation == epoch, self.requested else { return }
                self.starting = false
                // Don't blindly repeat a first permission request or an explicit
                // denial. Previously healthy streams may retry transient errors.
                let failure = error as? AudioTapError
                if failure?.permissionDenied == true ||
                    (failure?.creatingTap == true && !self.defaults.bool(forKey: Self.capturedKey)) {
                    self.needsRetry = true
                    self.defaults.set(true, forKey: Self.retryKey)
                    self.error = "System audio capture couldn't start (\(error)). Check System Audio Recording Only, then choose Retry visualizer."
                } else {
                    self.error = "Reconnecting the audio visualizer…"
                    self.scheduleRecovery(countFailure: true)
                }
            }
        }
    }

    private func beginHealthMonitoring() {
        guard monitorHealth else { return }
        healthTimer?.invalidate()
        healthTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkHealth() }
        }
        healthTimer?.tolerance = 0.2
    }

    /// Silence still produces FFT frames. Missing frames indicate a stalled
    /// callback, rather than a quiet song, and must not freeze the last bars.
    func checkHealth() {
        guard requested, tap != nil, !needsRetry, let reference = lastSpectrumTime ?? startedAt else { return }
        guard clock() - reference > 3 else { return }
        error = "Reconnecting the audio visualizer…"
        scheduleRecovery(countFailure: true)
    }

    private func scheduleRecovery(delay: Duration? = nil, countFailure: Bool) {
        guard requested, !suspended, !needsRetry else { return }
        // Coalesce format/routing notifications while a device settles.
        if recoveryTask != nil { return }
        invalidateCapture()
        if countFailure { consecutiveFailures += 1 }
        guard consecutiveFailures <= 6 else {
            needsRetry = true
            error = "Audio isn't delivering samples. Check the output device and audio permission, then choose Retry visualizer."
            return
        }
        let wait = delay ?? recoveryDelay(max(1, consecutiveFailures))
        let epoch = generation
        recoveryTask = Task { [weak self] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled, let self, self.generation == epoch else { return }
            self.recoveryTask = nil
            guard self.requested, !self.needsRetry else { return }
            self.start()
        }
    }

    private func invalidateCapture() {
        recoveryTask?.cancel(); recoveryTask = nil
        healthTimer?.invalidate(); healthTimer = nil
        let oldTap = tap
        tap = nil; starting = false; generation = UUID(); startedAt = nil
        compactSpectrum = CompactSpectrum(); lastSpectrumTime = nil
        compactLevels = CompactSpectrum.silence; levels = Self.restingLevels
        if let oldTap { dispose(oldTap) }
    }
}

/// Serialize Core Audio setup and destruction away from the main thread.
private enum AudioCaptureWorker {
    static let queue = DispatchQueue(label: "local.notch.visualizer.control", qos: .userInitiated)
    static func start(_ receiver: @escaping ([CGFloat]) -> Void, changed: @escaping () -> Void) async throws -> AudioCaptureStream {
        guard #available(macOS 14.2, *) else { throw AudioTapError.unsupportedOS }
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    // The analyzer is constructed here, then used exclusively by the
                    // stream's serial IO queue. Mutable FFT state never crosses actors.
                    let analyzer = SpectrumAnalyzer(count: 72, deliver: receiver)
                    let stream = try SystemAudioTap(analyzer: analyzer, changed: changed)
                    try stream.start()
                    continuation.resume(returning: stream)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
    static func stop(_ stream: AudioCaptureStream) { queue.async { stream.stop() } }
}

/// A private input-only aggregate device backed by a global Core Audio process
/// tap. It exists only while a visible playback visualizer needs audio.
@available(macOS 14.2, *)
private final class SystemAudioTap: AudioCaptureStream {
    private let queue = DispatchQueue(label: "app.notch.visualizer.tap", qos: .userInteractive)
    private let analyzer: SpectrumAnalyzer
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var format = AudioStreamBasicDescription()
    private var running = false
    private let changed: () -> Void
    private var listeners: [(AudioObjectID, AudioObjectPropertyAddress)] = []
    private lazy var listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.changed() }

    init(analyzer: SpectrumAnalyzer, changed: @escaping () -> Void) throws {
        self.analyzer = analyzer
        self.changed = changed
        do { try configure() }
        catch { stop(); throw error }
    }

    deinit { stop() }

    func start() throws {
        guard !running, let ioProcID else { return }
        try check(AudioDeviceStart(aggregateID, ioProcID), "start audio tap")
        running = true
    }

    func stop() {
        for (id, var address) in listeners {
            AudioObjectRemovePropertyListenerBlock(id, &address, AudioCaptureWorker.queue, listener)
        }
        listeners.removeAll()
        if running, let ioProcID { AudioDeviceStop(aggregateID, ioProcID) }
        running = false
        if let ioProcID {
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            self.ioProcID = nil
        }
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    private func configure() throws {
        let description = CATapDescription()
        description.name = "Notch Beat Visualizer"
        description.processes = []
        description.isPrivate = true
        description.isExclusive = true
        description.isMixdown = true
        description.isMono = false
        description.muteBehavior = .unmuted
        try check(AudioHardwareCreateProcessTap(description, &tapID), "create audio tap")

        var formatAddress = propertyAddress(kAudioTapPropertyFormat)
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check(AudioObjectGetPropertyData(tapID, &formatAddress, 0, nil, &formatSize, &format), "read tap format")
        guard format.mFormatID == kAudioFormatLinearPCM, format.mBitsPerChannel == 32,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mSampleRate > 0, format.mBytesPerFrame > 0 else { throw AudioTapError.missingFormat }

        var uidAddress = propertyAddress(kAudioTapPropertyUID)
        var uidSize = UInt32(MemoryLayout<CFString>.stride)
        var tapUID: CFString = "" as CFString
        let uidStatus = withUnsafeMutablePointer(to: &tapUID) { pointer in
            AudioObjectGetPropertyData(tapID, &uidAddress, 0, nil, &uidSize, pointer)
        }
        try check(uidStatus, "read tap identifier")

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Notch Visualizer",
            kAudioAggregateDeviceUIDKey: "local.notch.visualizer.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: tapUID,
                kAudioSubTapDriftCompensationKey: true
            ]]
        ]
        try check(AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregateID), "create visualizer device")

        let format = format
        let analyzer = analyzer
        let diagnostics = CommandLine.arguments.contains("--check-visualizer")
        if diagnostics {
            print("Tap format: rate=\(format.mSampleRate) channels=\(format.mChannelsPerFrame) bits=\(format.mBitsPerChannel) flags=\(format.mFormatFlags) bytesPerFrame=\(format.mBytesPerFrame)")
        }
        var callbackReported = false
        var proc: AudioDeviceIOProcID?
        try check(AudioDeviceCreateIOProcIDWithBlock(&proc, aggregateID, queue) { _, input, _, _, _ in
            if diagnostics && !callbackReported {
                callbackReported = true
                let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
                print("First callback: buffers=\(buffers.count) bytes=\(buffers.map { $0.mDataByteSize }) channels=\(buffers.map { $0.mNumberChannels })")
            }
            analyzer.process(bufferList: input, format: format)
        }, "create visualizer callback")
        ioProcID = proc
        listen(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice)
        listen(tapID, kAudioTapPropertyFormat)
        listen(aggregateID, kAudioDevicePropertyDeviceIsAlive)
        var outputAddress = propertyAddress(kAudioHardwarePropertyDefaultOutputDevice)
        var output = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        if AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &outputAddress, 0, nil, &size, &output) == noErr,
           output != kAudioObjectUnknown {
            listen(output, kAudioDevicePropertyNominalSampleRate)
        }
    }

    private func listen(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) {
        var address = propertyAddress(selector)
        if AudioObjectAddPropertyListenerBlock(object, &address, AudioCaptureWorker.queue, listener) == noErr {
            listeners.append((object, address))
        }
    }

    private func check(_ status: OSStatus, _ operation: String) throws {
        guard status == noErr else { throw AudioTapError.coreAudio(operation: operation, status: status) }
    }

    private func propertyAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector,
                                   mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }
}

final class SpectrumAnalyzer {
    private let count: Int
    private let deliver: ([CGFloat]) -> Void
    private let fftSize = 2_048
    private let log2FFT = vDSP_Length(11)
    private lazy var fftSetup = vDSP_create_fftsetup(log2FFT, FFTRadix(kFFTRadix2))
    private lazy var window: [Float] = {
        var values = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&values, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        return values
    }()
    private var smoothed: [Float]
    private var previousTargets: [Float]
    private var samples = [Float](repeating: 0, count: 2_048)
    private var writeIndex = 0
    private var sampleCount = 0
    private var pendingFrames = 0

    init(count: Int, deliver: @escaping ([CGFloat]) -> Void) {
        self.count = count
        self.deliver = deliver
        smoothed = Array(repeating: 0, count: count)
        previousTargets = Array(repeating: 0, count: count)
    }

    deinit {
        if let fftSetup { vDSP_destroy_fftsetup(fftSetup) }
    }

    func process(bufferList: UnsafePointer<AudioBufferList>, format: AudioStreamBasicDescription) {
        guard format.mFormatID == kAudioFormatLinearPCM,
              format.mBitsPerChannel == 32,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mSampleRate > 0 else { return }

        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferList))
        guard let first = buffers.first, first.mData != nil else { return }
        let nonInterleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        let channels = max(1, Int(format.mChannelsPerFrame))
        let bytesPerFrame = max(4, Int(format.mBytesPerFrame))
        let frames = Int(first.mDataByteSize) / bytesPerFrame
        guard frames > 0 else { return }
        let channelCount = nonInterleaved ? min(channels, buffers.count) : max(1, Int(first.mNumberChannels))
        let hop = max(1, Int(format.mSampleRate / 60))
        // Keep a complete rolling window. Zero-padding each small callback at
        // the end of a Hann window erased most of the signal and its dynamics.
        for frame in 0..<frames {
            var sample: Float = 0
            for channel in 0..<channelCount {
                let buffer = nonInterleaved ? buffers[channel] : first
                let index = nonInterleaved ? frame : frame * channelCount + channel
                guard index < Int(buffer.mDataByteSize) / MemoryLayout<Float>.size,
                      let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                let input = data[index]
                if input.isFinite { sample += input / Float(channelCount) }
            }
            samples[writeIndex] = sample
            writeIndex = (writeIndex + 1) % fftSize
            sampleCount = min(fftSize, sampleCount + 1)
            pendingFrames += 1
            if sampleCount == fftSize, pendingFrames >= hop {
                pendingFrames = 0
                analyze(sampleRate: Float(format.mSampleRate))
            }
        }
    }

    private func analyze(sampleRate: Float) {
        guard let fftSetup else { return }
        var mono = (0..<fftSize).map { samples[(writeIndex + $0) % fftSize] }

        vDSP_vmul(mono, 1, window, 1, &mono, 1, vDSP_Length(fftSize))
        var real = [Float](repeating: 0, count: fftSize / 2)
        var imaginary = [Float](repeating: 0, count: fftSize / 2)
        var power = [Float](repeating: 0, count: fftSize / 2)
        mono.withUnsafeBufferPointer { monoPointer in
            real.withUnsafeMutableBufferPointer { realPointer in
                imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
                    var split = DSPSplitComplex(realp: realPointer.baseAddress!, imagp: imaginaryPointer.baseAddress!)
                    monoPointer.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) { complexPointer in
                        vDSP_ctoz(complexPointer, 2, &split, 1, vDSP_Length(fftSize / 2))
                    }
                    vDSP_fft_zrip(fftSetup, &split, 1, log2FFT, FFTDirection(kFFTDirection_Forward))
                    vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(fftSize / 2))
                }
            }
        }

        let maximumFrequency = min(16_000, sampleRate * 0.47)
        let logMinimum = log(Float(48))
        let logRange = log(maximumFrequency) - logMinimum
        var targets = [Float](repeating: 0, count: count)
        for index in 0..<count {
            let lower = exp(logMinimum + logRange * Float(index) / Float(count))
            let upper = exp(logMinimum + logRange * Float(index + 1) / Float(count))
            let lowerBin = max(1, min(power.count - 1, Int(lower * Float(fftSize) / sampleRate)))
            let upperBin = max(lowerBin + 1, min(power.count, Int(ceil(upper * Float(fftSize) / sampleRate))))
            let band = power[lowerBin..<upperBin]
            let averagePower = band.reduce(0, +) / Float(max(1, band.count))
            let amplitude = sqrt(max(averagePower, 0)) / Float(fftSize)
            let decibels = 20 * log10(max(amplitude, 0.000_01))
            targets[index] = pow(min(1, max(0, (decibels + 66) / 54)), 1.4)
        }

        for index in 0..<count {
            // Each band responds independently: a kick must not raise every
            // bar into a solid rectangle. Fast attack, gently falling tails.
            let onset = max(0, targets[index] - previousTargets[index])
            let target = min(1, targets[index] + onset * 0.35)
            let smoothing: Float = target > smoothed[index] ? 0.82 : 0.22
            smoothed[index] += (target - smoothed[index]) * smoothing
        }
        previousTargets = targets
        deliver(smoothed.map(CGFloat.init))
    }
}
