import SwiftUI
import ServiceManagement
import NotchCore

struct SettingsView: View {
    @ObservedObject var state: AppState
    @State private var section = "General"
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    private let sections = [("General", "slider.horizontal.3"), ("Activities", "square.stack.3d.up"), ("Tracked Apps", "sparkle"), ("Appearance", "paintpalette"), ("Shortcuts", "command"), ("About", "circle.lefthalf.filled")]
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 10) {
                    Image(systemName: "circle.lefthalf.filled").font(.system(size: 26))
                    VStack(alignment: .leading, spacing: 2) { Text("Notch").font(.system(size: 18, weight: .semibold)); Text("A quieter kind of useful.").font(.system(size: 9)).foregroundStyle(.secondary) }
                }.padding(.bottom, 25).padding(.top, 17)
                ForEach(sections, id: \.0) { title, symbol in
                    Button { section = title } label: {
                        Label(title, systemImage: symbol).font(.system(size: 12, weight: .medium)).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.vertical, 9)
                            .background(section == title ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 7))
                    }.buttonStyle(.plain)
                }
                Spacer()
                Text("VERSION 1.1").font(.system(size: 9, weight: .medium)).tracking(1.5).foregroundStyle(.tertiary).padding(.bottom, 9)
            }.padding(16).frame(width: 185).background(.regularMaterial)
            VStack(alignment: .leading, spacing: 0) {
                Text(section).font(.system(size: 25, weight: .semibold)).padding(.horizontal, 24).padding(.top, 28).padding(.bottom, 12)
                Form {
                    switch section {
                    case "General": general
                    case "Activities": activities
                    case "Tracked Apps": trackedApps
                    case "Appearance": appearance
                    case "Shortcuts": shortcuts
                    default: about
                    }
                }.formStyle(.grouped).scrollContentBackground(.hidden)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.frame(width: 730, height: 555)
    }
    private func binding<T>(_ key: WritableKeyPath<Preferences, T>) -> Binding<T> {
        Binding(get: { state.preferences[keyPath: key] }, set: { state.preferences[keyPath: key] = $0 })
    }
    private var general: some View {
        Group {
            Section {
                Text("Your music, focus, and system controls.").font(.system(size: 13)).foregroundStyle(.secondary)
                Toggle("Open when I hover", isOn: binding(\.hoverEnabled))
                if state.preferences.hoverEnabled {
                    HStack { Text("Hover delay"); Slider(value: binding(\.hoverDelay), in: 0.15...0.8, step: 0.05); Text(String(format: "%.2fs", state.preferences.hoverDelay)).monospacedDigit().frame(width: 45) }
                }
                Picker("Display", selection: binding(\.selectedDisplay)) {
                    Text("Automatic · prefer built-in notch").tag(UInt32(0))
                    ForEach(NSScreen.screens, id: \.displayID) { screen in Text(screen.localizedName).tag(screen.displayID) }
                }
            }
            Section("Keyboard HUD") {
                Toggle("Use Notch for volume and brightness keys", isOn: Binding(get: { state.preferences.replaceSystemHUD != false }, set: { state.preferences.replaceSystemHUD = $0 }))
                Text(state.mediaKeys.status).font(.caption).foregroundStyle(state.mediaKeys.active ? Color.secondary : .orange)
                if !state.mediaKeys.active && state.preferences.replaceSystemHUD != false {
                    Button("Enable Accessibility…") { state.mediaKeys.requestAccess() }
                }
                Text("Notch handles only volume, mute, and brightness keys. When Notch quits, macOS handles them again. Until Accessibility is active, the system HUD remains in control and Notch waits instead of showing duplicate feedback.").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Launch at login", isOn: Binding(get: { loginEnabled }, set: setLogin))
                if let loginError { Text(loginError).foregroundStyle(.orange).font(.caption) }
                Text("Full-screen apps stay quiet. Click Notch or use your shortcut to open it in full screen.").font(.caption).foregroundStyle(.secondary)
                Text("If Atoll, Notchy, or Lemon also occupies the notch, pause its notch overlay to avoid overlapping controls.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var activities: some View {
        Group {
            Section("Enabled features") {
                Toggle("Music · apps and browser playback", isOn: binding(\.musicEnabled))
                Toggle("Timer", isOn: binding(\.timerEnabled))
                Toggle("Keep Awake", isOn: binding(\.powerEnabled))
                Toggle("Battery status", isOn: binding(\.batteryEnabled))
                Toggle("AirPods and Beats connection animation", isOn: Binding(get: { state.preferences.bluetoothAlertsEnabled != false }, set: { state.preferences.bluetoothAlertsEnabled = $0 }))
                    .help("Show Apple headset connections inside the notch. Other Bluetooth devices stay quiet.")
                if let error = state.bluetooth.error { Text(error).foregroundStyle(.orange).font(.caption) }
                Toggle("Output volume", isOn: binding(\.volumeEnabled))
                Toggle("Display brightness", isOn: Binding(get: { state.preferences.brightnessEnabled != false }, set: { state.preferences.brightnessEnabled = $0 }))
                Toggle("Volume and brightness feedback", isOn: Binding(get: { state.preferences.hudEnabled != false }, set: { state.preferences.hudEnabled = $0 }))
                Toggle("Play a sound when a timer finishes", isOn: binding(\.completionSound))
                Text("Turning Timer off cancels its countdown. Turning Keep Awake off releases its sleep assertion.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Favorite order") {
                ForEach(Array(state.preferences.favorites.enumerated()), id: \.element) { index, activity in
                    HStack {
                        Label(activity.title, systemImage: activity.symbol)
                        Spacer()
                        Button { state.preferences.favorites.swapAt(index, index - 1) } label: { Image(systemName: "chevron.up") }.disabled(index == 0).help("Move earlier")
                        Button { state.preferences.favorites.swapAt(index, index + 1) } label: { Image(systemName: "chevron.down") }.disabled(index == state.preferences.favorites.count - 1).help("Move later")
                    }
                }
            }
        }
    }
    private var trackedApps: some View {
        Group {
            Section("Media") {
                Text("Browser media uses macOS Now Playing automatically. Up/down swipes switch between available media sources; left/right swipes switch widgets.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Connect Spotify") { state.music.connect(.spotify) }
                    Button("Connect Apple Music") { state.music.connect(.appleMusic) }
                }
                ForEach(MusicSource.allCases) { source in
                    if let message = state.music.messages[source] { Text(message).font(.caption).foregroundStyle(.orange) }
                }
                Text("macOS shares one system media session at a time. Browsers must publish their media to Now Playing. Separate browser tabs will need the later extension.").font(.caption).foregroundStyle(.secondary)
            }
            AudioCaptureSettings(service: state.visualizer)
            Section {
                Toggle("Track Codex usage", isOn: binding(\.codexEnabled))
                Text("Codex gets its own bubble. Turning tracking off stops collection and removes the bubble.").font(.caption).foregroundStyle(.secondary)
                if state.preferences.codexEnabled {
                    LabeledContent("Connection", value: state.codex.status)
                    if let error = state.codex.lastError { Text(error).font(.caption).foregroundStyle(.orange) }
                    HStack { Button("Refresh usage") { state.codex.refresh() }.disabled(state.codex.fetching); Button("Open Codex") { openCodex() } }
                }
            }
            Section("Connection") {
                HStack { Text("Codex executable"); Spacer(); Button("Choose…") { chooseCodex() } }
                Text(state.codex.resolvedBinary ?? "Not found automatically").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                if !state.preferences.codexPath.isEmpty { Button("Use automatic discovery") { state.preferences.codexPath = "" } }
                Text("Uses Codex’s local protocol and your existing sign-in. No API key is needed. Percentages describe subscription quota, not a fixed token allowance.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var appearance: some View {
        Group {
            Section {
                Picker("Accent", selection: binding(\.accent)) { Text("Neutral").tag("neutral"); Text("Blue").tag("blue"); Text("Mint").tag("mint"); Text("Peach").tag("peach") }.pickerStyle(.segmented)
                HStack { Text("Compact spacing"); Slider(value: binding(\.compactScale), in: 0.85...1.2, step: 0.05) }
                Picker("Primary activity", selection: Binding(get: { state.preferences.primary?.rawValue ?? "automatic" }, set: { state.preferences.primary = ActivityID(rawValue: $0) })) {
                    Text("Automatic · music first").tag("automatic")
                    Text("Pin music").tag("music"); Text("Pin timer").tag("timer"); Text("Pin Codex").tag("codex")
                }
                Text("Pinned activities take the main notch when available. Circular activity bubbles sit directly beside it. Click a circle for details.").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Text("Playback bars animate while music plays and settle when paused. They indicate playback, without recording audio. Reduce Motion keeps them still. Keyboard opening is immediate.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var shortcuts: some View {
        Section {
            Toggle("Enable global shortcut", isOn: binding(\.shortcutEnabled))
            Picker("Open / close Notch", selection: binding(\.shortcutKey)) { ForEach(["N", "K", "J", "Space"], id: \.self) { key in Text("⌥ ⌘ \(key)").tag(key) } }
            if let error = state.shortcutError { Text(error).foregroundStyle(.orange).font(.caption) }
            LabeledContent("Dismiss the focused notch", value: "Esc")
            Text("Hover for playback controls. The compact music bars and hovered media scrubber follow system audio while visible. Click the artwork for lyrics; use the back arrow to return. Swipe sideways to switch widgets, or vertically in the player to switch sources.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var about: some View {
        Group {
            Section {
                Text("Notch").font(.largeTitle.weight(.semibold))
                Text("A small, native home for what’s happening now.").foregroundStyle(.secondary)
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.1.0")
                LabeledContent("Built for", value: "Intel & Apple silicon · macOS 13+")
            }
            UpdateSettings(service: state.updates)
            Section("Your data") {
                Text("Settings and timer state stay on this Mac. Music artwork comes from the player. Opening lyrics sends the track title, artist, album, and duration to LRCLIB. Codex reads quota through its local signed-in service. Notch adds no analytics or cloud account.").font(.callout).foregroundStyle(.secondary)
                Text("Planned next: v1.2 file shelf; v1.3 opt-in clipboard history and snippets; v1.4 calendar and reminders.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func setLogin(_ value: Bool) {
        do {
            if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            loginError = SMAppService.mainApp.status == .requiresApproval ? "Allow Notch in System Settings → General → Login Items." : nil
        } catch { loginError = "macOS could not update Login Items. Install Notch in Applications and try again."; loginEnabled = SMAppService.mainApp.status == .enabled }
    }
    private func chooseCodex() {
        let picker = NSOpenPanel(); picker.canChooseDirectories = false; picker.allowsMultipleSelection = false; picker.message = "Choose the Codex executable."
        if picker.runModal() == .OK, let url = picker.url { state.preferences.codexPath = url.path }
    }
    private func openCodex() {
        let candidates = ["/Applications/Codex.app", "/Applications/ChatGPT.app"]
        if let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
    }
}

private struct UpdateSettings: View {
    @ObservedObject var service: UpdateService
    var body: some View {
        Section("Updates") {
            Toggle("Automatically check for updates", isOn: Binding(
                get: { service.automaticallyChecksForUpdates }, set: { service.setAutomaticChecks($0) }))
                .disabled(!service.configured)
            Toggle("Automatically download and install updates", isOn: Binding(
                get: { service.automaticallyDownloadsUpdates }, set: { service.setAutomaticDownloads($0) }))
                .disabled(!service.configured)
            Button("Check for Updates…") { service.checkForUpdates() }
                .disabled(!service.canCheckForUpdates)
            if let date = service.lastUpdateCheckDate {
                LabeledContent("Last checked") { Text(date, format: .dateTime.month().day().hour().minute()) }
            }
            Text(service.configured ? "Updates are checked hourly and verified before installation. Automatic updates install when Notch quits or relaunches." : service.status)
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct AudioCaptureSettings: View {
    @ObservedObject var service: AudioVisualizerService
    var body: some View {
        Section("Audio visualizer") {
            Text(service.isSupported ? "Uses System Audio Recording Only while music is visible in the compact notch or you hover over the playback slider. No microphone or screen recording access is needed." : "Audio-reactive bars need macOS Sonoma 14.2 or later. Artwork, playback, seeking and lyrics still work on this Mac.")
                .font(.caption).foregroundStyle(.secondary)
            if let error = service.error {
                Text(error).font(.caption).foregroundStyle(.orange)
            }
            if service.isSupported {
                HStack {
                    Button("Audio permission settings…") { service.openAudioSettings() }
                    if service.needsRetry {
                        Button("Retry visualizer") { service.retry() }
                    }
                }
            }
        }
    }
}
