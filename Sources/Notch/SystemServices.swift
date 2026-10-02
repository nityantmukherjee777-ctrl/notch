import AppKit
import Combine
import CoreAudio
import IOKit.ps
import IOKit.pwr_mgt
import NotchCore

@MainActor final class TimerService: ObservableObject {
    @Published private(set) var countdown: Countdown
    @Published private(set) var now = Date()
    var onCompletion: (() -> Void)?
    private var ticker: Timer?
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        countdown = defaults.data(forKey: "countdown").flatMap { try? JSONDecoder().decode(Countdown.self, from: $0) } ?? Countdown()
        countdown.sanitize(at: now)
        tick(); schedule()
    }
    var remaining: TimeInterval { countdown.remaining(at: now) }
    func start(name: String, minutes: Double) {
        now = Date(); countdown.start(name: name, seconds: minutes * 60, now: now); save(); schedule()
    }
    func togglePause() {
        now = Date()
        if countdown.isPaused { countdown.resume(at: now) } else { countdown.pause(at: now) }
        save(); schedule()
    }
    func reset() { countdown.reset(); save(); schedule() }
    func wake() { tick(); schedule() }
    private func schedule() {
        ticker?.invalidate(); ticker = nil
        guard countdown.isRunning else { return }
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        ticker?.tolerance = 0.1
    }
    private func tick() {
        now = Date()
        if countdown.reconcile(at: now) { save(); schedule(); onCompletion?() }
    }
    private func save() { defaults.set(try? JSONEncoder().encode(countdown), forKey: "countdown") }
}

@MainActor final class PowerService: ObservableObject {
    @Published private(set) var isAwake = false
    @Published private(set) var until: Date?
    @Published private(set) var error: String?
    private var assertion: IOPMAssertionID = 0
    private var expiry: Timer?
    func toggle(minutes: Int = 0) { isAwake ? stop() : start(minutes: minutes) }
    func start(minutes: Int) {
        stop()
        let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn), "Notch Keep Awake" as CFString, &assertion)
        guard result == kIOReturnSuccess else { error = "macOS could not start Keep Awake."; return }
        isAwake = true; error = nil
        if minutes > 0 {
            let duration = Double(min(1440, minutes)) * 60
            until = Date().addingTimeInterval(duration)
            expiry = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.stop() }
            }
        }
    }
    func stop() {
        expiry?.invalidate(); expiry = nil
        if assertion != 0 { IOPMAssertionRelease(assertion); assertion = 0 }
        isAwake = false; until = nil
    }
    func wake(at now: Date = Date()) { if let until, until <= now { stop() } }
}

@MainActor final class BatteryService: ObservableObject {
    @Published private(set) var percent: Int?
    @Published private(set) var charging = false
    @Published private(set) var pluggedIn = false
    private var source: CFRunLoopSource?
    private var enabled = false
    func configure(enabled: Bool) {
        guard enabled != self.enabled else { return }
        self.enabled = enabled
        if enabled {
            let pointer = Unmanaged.passUnretained(self).toOpaque()
            source = IOPSNotificationCreateRunLoopSource({ pointer in
                guard let pointer else { return }
                let service = Unmanaged<BatteryService>.fromOpaque(pointer).takeUnretainedValue()
                Task { @MainActor in service.refresh() }
            }, pointer)?.takeRetainedValue()
            if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
            refresh()
        } else {
            if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
            source = nil; percent = nil
        }
    }
    func refresh() {
        guard enabled, let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maxCapacity = description[kIOPSMaxCapacityKey] as? Int, maxCapacity > 0 else { continue }
            let plugged = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let newPercent = Int(min(100, max(0, Double(current) / Double(maxCapacity) * 100)))
            if percent != newPercent { percent = newPercent }
            let newCharging = description[kIOPSIsChargingKey] as? Bool ?? false
            if charging != newCharging { charging = newCharging }
            if pluggedIn != plugged { pluggedIn = plugged }
            return
        }
        percent = nil
    }
}

@MainActor final class AudioService: ObservableObject {
    @Published private(set) var volume: Float = 0
    @Published private(set) var muted = false
    @Published private(set) var canSetVolume = false
    @Published private(set) var canMute = false
    @Published private(set) var deviceName = "System output"
    @Published private(set) var error: String?
    private var hasReading = false
    var onChange: ((Float, Bool) -> Void)?
    var onUserChange: ((Float, Bool) -> Void)?
    private var listeners: [(AudioObjectID, AudioObjectPropertyAddress)] = []
    private lazy var listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        Task { @MainActor in self?.refresh() }
    }
    private func clearListeners() {
        for (id, var address) in listeners { AudioObjectRemovePropertyListenerBlock(id, &address, .main, listener) }
        listeners.removeAll()
    }
    private func listen(_ id: AudioObjectID, _ address: AudioObjectPropertyAddress) {
        var address = address
        if AudioObjectAddPropertyListenerBlock(id, &address, .main, listener) == noErr { listeners.append((id, address)) }
    }
    private var device = AudioDeviceID(0)
    private var refreshTimer: Timer?
    private var volumeElements: [AudioObjectPropertyElement] = []
    private var enabled = false
    func configure(enabled: Bool) {
        guard enabled != self.enabled else { return }
        self.enabled = enabled; refreshTimer?.invalidate(); refreshTimer = nil
        clearListeners(); device = 0; hasReading = false
        if enabled {
            refresh()
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } }
            refreshTimer?.tolerance = 1
        }
    }
    private func address(_ selector: AudioObjectPropertySelector, element: AudioObjectPropertyElement = 0, global: Bool = false) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: global ? kAudioObjectPropertyScopeGlobal : kAudioDevicePropertyScopeOutput, mElement: element)
    }
    private func isWritable(_ selector: AudioObjectPropertySelector, element: AudioObjectPropertyElement = 0) -> Bool {
        var a = address(selector, element: element), writable = DarwinBoolean(false)
        return AudioObjectHasProperty(device, &a) && AudioObjectIsPropertySettable(device, &a, &writable) == noErr && writable.boolValue
    }
    func refresh() {
        guard enabled else { return }
        var a = address(kAudioHardwarePropertyDefaultOutputDevice, global: true), size = UInt32(MemoryLayout<AudioDeviceID>.size), current = AudioDeviceID(0)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &current) == noErr, current != 0 else {
            canSetVolume = false; canMute = false; return
        }
        let changedDevice = device != current
        let oldVolume = volume, oldMuted = muted
        device = current
        if changedDevice {
            clearListeners()
            listen(AudioObjectID(kAudioObjectSystemObject), address(kAudioHardwarePropertyDefaultOutputDevice, global: true))
            for element: UInt32 in [0, 1, 2] { listen(device, address(kAudioDevicePropertyVolumeScalar, element: element)) }
            listen(device, address(kAudioDevicePropertyMute))
        }
        a = address(kAudioObjectPropertyName, global: true)
        var name: Unmanaged<CFString>?; size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        if AudioObjectGetPropertyData(device, &a, 0, nil, &size, &name) == noErr, let name {
            let value = name.takeRetainedValue() as String
            if deviceName != value { deviceName = value }
        }
        volumeElements = isWritable(kAudioDevicePropertyVolumeScalar) ? [0] : [1, 2].filter { isWritable(kAudioDevicePropertyVolumeScalar, element: $0) }
        if canSetVolume != !volumeElements.isEmpty { canSetVolume = !volumeElements.isEmpty }
        let muteAvailable = isWritable(kAudioDevicePropertyMute)
        if canMute != muteAvailable { canMute = muteAvailable }
        if let element = volumeElements.first {
            a = address(kAudioDevicePropertyVolumeScalar, element: element); size = UInt32(MemoryLayout<Float32>.size); var scalar = Float32(0)
            if AudioObjectGetPropertyData(device, &a, 0, nil, &size, &scalar) == noErr, scalar.isFinite, abs(volume - scalar) > 0.005 { volume = min(1, max(0, scalar)) }
        }
        a = address(kAudioDevicePropertyMute); size = UInt32(MemoryLayout<UInt32>.size); var mute: UInt32 = 0
        if AudioObjectGetPropertyData(device, &a, 0, nil, &size, &mute) == noErr, muted != (mute != 0) { muted = mute != 0 }
        if hasReading && !changedDevice && (abs(oldVolume - volume) > 0.005 || oldMuted != muted) { onChange?(volume, muted) }
        hasReading = true
    }
    func setVolume(_ value: Float) {
        guard canSetVolume, value.isFinite else { return }
        var scalar = min(1, max(0, value)); var succeeded = true
        for element in volumeElements {
            var a = address(kAudioDevicePropertyVolumeScalar, element: element)
            succeeded = AudioObjectSetPropertyData(device, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &scalar) == noErr && succeeded
        }
        if succeeded { volume = scalar; error = nil; onUserChange?(volume, muted) } else { error = "This output could not change volume."; refresh() }
    }
    func toggleMute() {
        guard canMute else { return }
        var value: UInt32 = muted ? 0 : 1; var a = address(kAudioDevicePropertyMute)
        if AudioObjectSetPropertyData(device, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr { muted.toggle(); error = nil; onUserChange?(volume, muted) }
        else { error = "This output could not change mute."; refresh() }
    }
}
