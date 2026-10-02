import AppKit
import Combine
import NotchCore

@MainActor final class AppState: ObservableObject {
    @Published var preferences: Preferences { didSet { save(); configure() } }
    @Published var selected: ActivityID = .music {
        didSet {
            music.setExpanded(expanded && selected == .music)
            if expanded && selected == .codex { codex.refresh() }
            DispatchQueue.main.async { self.onLayoutChange?() }
        }
    }
    @Published var expanded = false
    /// Keeps the expanded hierarchy alive while the surface finishes collapsing.
    @Published var presentingExpanded = false
    @Published var mediaDetail = false
    @Published var surfaceSize = CGSize(width: 180, height: 32)
    @Published var hud: HUDReading?
    @Published private(set) var hardwareHUD = false
    let lyrics = LyricsService()
    let brightness = BrightnessService()
    let mediaKeys = MediaKeyService()
    private var handlingHardwareKey = false
    private var hudTask: Task<Void, Never>?
    func showHUD(_ reading: HUDReading) {
        guard preferences.hudEnabled != false else { return }
        hudTask?.cancel(); hardwareHUD = handlingHardwareKey; hud = reading; onLayoutChange?()
        hudTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            self?.hud = nil; self?.onLayoutChange?()
        }
    }
    func cycleWidget(_ direction: Int) {
        let items = enabledActivities
        guard let index = items.firstIndex(of: selected), !items.isEmpty else { return }
        mediaDetail = false
        selected = items[(index + direction + items.count) % items.count]
        onLayoutChange?()
    }
    @Published var transientMessage: String?
    @Published var shortcutError: String?
    let music = MusicService()
    let timer = TimerService()
    let power = PowerService()
    let battery = BatteryService()
    let bluetooth = BluetoothService()
    let audio = AudioService()
    let visualizer = AudioVisualizerService()
    let codex = CodexService()
    let updates = UpdateService()
    var openSettings: (() -> Void)?
    var onLayoutChange: (() -> Void)?
    private var subscriptions: Set<AnyCancellable> = []
    private var notificationTokens: [NSObjectProtocol] = []
    private var toastTask: Task<Void, Never>?
    init() {
        var saved = UserDefaults.standard.data(forKey: "preferences").flatMap { try? JSONDecoder().decode(Preferences.self, from: $0) } ?? Preferences()
        if !UserDefaults.standard.bool(forKey: "neutralAppearanceMigration") {
            if saved.accent == "mint" { saved.accent = "neutral" }
            UserDefaults.standard.set(true, forKey: "neutralAppearanceMigration")
        }
        saved.sanitize()
        preferences = saved
        save()
        for publisher in [music.objectWillChange.eraseToAnyPublisher(), timer.objectWillChange.eraseToAnyPublisher(), power.objectWillChange.eraseToAnyPublisher(), battery.objectWillChange.eraseToAnyPublisher(), bluetooth.objectWillChange.eraseToAnyPublisher(), audio.objectWillChange.eraseToAnyPublisher(), codex.objectWillChange.eraseToAnyPublisher(), lyrics.objectWillChange.eraseToAnyPublisher(), brightness.objectWillChange.eraseToAnyPublisher(), mediaKeys.objectWillChange.eraseToAnyPublisher()] {
            publisher.sink { [weak self] in
                self?.objectWillChange.send()
                DispatchQueue.main.async { self?.onLayoutChange?() }
            }.store(in: &subscriptions)
        }
        timer.onCompletion = { [weak self] in
            guard let self else { return }
            if self.preferences.completionSound { NSSound(named: "Glass")?.play() }
            self.toast("\(self.timer.countdown.name) finished")
        }
        let center = NSWorkspace.shared.notificationCenter
        notificationTokens.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.visualizer.suspend() }
        })
        notificationTokens.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.timer.wake(); self?.power.wake(); self?.battery.refresh(); self?.audio.refresh(); self?.codex.refresh(); self?.music.refresh(); self?.mediaKeys.recover(); self?.visualizer.recover(); self?.onLayoutChange?() }
        })
        notificationTokens.append(center.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.mediaKeys.recover(); self?.visualizer.recover() }
        })
        notificationTokens.append(center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.music.refresh(); self?.codex.updateActivityVisibility() } })
        notificationTokens.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.music.refresh(); self?.codex.updateActivityVisibility() } })
        audio.onUserChange = { [weak self] value, muted in
            guard let self, !self.handlingHardwareKey else { return }
            self.showHUD(HUDReading(kind: .volume, value: muted ? 0 : Double(value), muted: muted))
        }
        audio.onChange = { [weak self] value, muted in
            guard let self, self.preferences.replaceSystemHUD == false, !self.handlingHardwareKey else { return }
            self.showHUD(HUDReading(kind: .volume, value: muted ? 0 : Double(value), muted: muted))
        }
        brightness.onUserChange = { [weak self] value in
            guard let self, !self.handlingHardwareKey else { return }
            self.showHUD(HUDReading(kind: .brightness, value: Double(value)))
        }
        brightness.onChange = { [weak self] value in
            guard let self, self.preferences.replaceSystemHUD == false, !self.handlingHardwareKey else { return }
            self.showHUD(HUDReading(kind: .brightness, value: Double(value)))
        }
        mediaKeys.handle = { [weak self] control, step in self?.handleHardwareKey(control, step: step) ?? false }
        configure()
    }
    private func handleHardwareKey(_ control: HardwareControl, step: Double) -> Bool {
        handlingHardwareKey = true
        defer { handlingHardwareKey = false }
        switch control {
        case .volumeUp, .volumeDown:
            guard preferences.volumeEnabled else { return false }
            audio.refresh()
            guard audio.canSetVolume else { return false }
            let target = Float(control.adjusted(Double(audio.volume), step: step))
            audio.setVolume(target)
            guard audio.error == nil else { return false }
            if audio.muted && audio.canMute { audio.toggleMute() }
            // A successful hardware write owns this key. Immediate readback can
            // lag, so passing it to macOS would apply it twice and show two HUDs.
            showHUD(HUDReading(kind: .volume, value: Double(audio.volume), muted: audio.muted))
            return true
        case .mute:
            guard preferences.volumeEnabled else { return false }
            audio.refresh(); guard audio.canMute else { return false }
            audio.toggleMute()
            if audio.error == nil { showHUD(HUDReading(kind: .volume, value: audio.muted ? 0 : Double(audio.volume), muted: audio.muted)) }
            return audio.error == nil
        case .brightnessUp, .brightnessDown:
            guard preferences.brightnessEnabled != false else { return false }
            brightness.refresh(); guard let value = brightness.value else { return false }
            let target = Float(max(0.05, control.adjusted(Double(value), step: step)))
            brightness.set(target)
            let success = brightness.error == nil
            if success { showHUD(HUDReading(kind: .brightness, value: Double(brightness.value ?? target))) }
            return success
        }
    }
    func configure() {
        music.configure(enabled: preferences.musicEnabled)
        if !preferences.musicEnabled { visualizer.stop(); lyrics.clear() }
        battery.configure(enabled: preferences.batteryEnabled)
        bluetooth.configure(enabled: preferences.bluetoothAlertsEnabled != false)
        audio.configure(enabled: preferences.volumeEnabled)
        brightness.configure(enabled: preferences.brightnessEnabled != false)
        mediaKeys.configure(enabled: preferences.hudEnabled != false && preferences.replaceSystemHUD != false)
        if preferences.hudEnabled == false { hudTask?.cancel(); hud = nil }
        codex.configure(enabled: preferences.codexEnabled, path: preferences.codexPath)
        if !preferences.powerEnabled { power.stop() }
        if !preferences.timerEnabled { timer.reset() }
        if !isEnabled(selected) { selected = enabledActivities.first ?? .power }
        onLayoutChange?()
    }
    func shutdown() { mediaKeys.stop(); visualizer.stop(); power.stop(); codex.stop(); bluetooth.stop(); music.configure(enabled: false); battery.configure(enabled: false); audio.configure(enabled: false); brightness.configure(enabled: false); lyrics.clear() }
    func save() { UserDefaults.standard.set(try? JSONEncoder().encode(preferences), forKey: "preferences") }
    func toast(_ message: String) {
        // Feedback remains compact, including in full-screen apps. It never opens a panel.
        toastTask?.cancel(); transientMessage = message; onLayoutChange?()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.transientMessage = nil; self?.onLayoutChange?()
        }
    }
    var enabledActivities: [ActivityID] { preferences.favorites.filter(isEnabled) + ActivityID.allCases.filter { !preferences.favorites.contains($0) && isEnabled($0) } }
    func isEnabled(_ id: ActivityID) -> Bool {
        switch id { case .music: return preferences.musicEnabled; case .timer: return preferences.timerEnabled; case .codex: return preferences.codexEnabled; case .power: return preferences.powerEnabled }
    }
    var primary: ActivityID? {
        ActivityLayout.primary(pinned: preferences.primary, musicPlaying: preferences.musicEnabled && music.track?.playing == true,
            timerActive: preferences.timerEnabled && timer.countdown.isActive, codexEnabled: preferences.codexEnabled)
    }
    var satellites: [ActivityID] {
        ActivityLayout.satellites(primary: primary, timerActive: preferences.timerEnabled && timer.countdown.isActive, codexEnabled: preferences.codexEnabled && codex.bubbleVisible, musicActive: preferences.musicEnabled && music.track?.playing == true)
    }
    var activities: [LiveActivity] {
        enabledActivities.map { id in
            switch id {
            case .music: return LiveActivity(id: id, provider: music.track?.source.name ?? "Music", title: music.track?.title ?? "Nothing playing", detail: music.track?.artist ?? "", isActive: music.track != nil, actions: ["playpause", "previous", "next", "seek"])
            case .timer: return LiveActivity(id: id, provider: "Notch", title: timer.countdown.name, detail: clockString(timer.remaining), isActive: timer.countdown.isActive, actions: ["start", "pause", "resume", "reset"])
            case .codex: return LiveActivity(id: id, provider: "Codex", title: "Codex usage", detail: codex.status, isActive: preferences.codexEnabled, actions: ["refresh"])
            case .power: return LiveActivity(id: id, provider: "macOS", title: "Keep Awake", detail: power.isAwake ? "On" : "Off", isActive: power.isAwake, actions: ["toggle"])
            }
        }
    }
}
