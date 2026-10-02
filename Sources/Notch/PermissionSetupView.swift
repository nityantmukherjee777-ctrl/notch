import SwiftUI
import ApplicationServices
import NotchCore

struct PermissionSetupView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var visualizer: AudioVisualizerService
    init(state: AppState) { self.state = state; self.visualizer = state.visualizer }
    @State private var accessibilityGranted = AXIsProcessTrusted()
    private var location: InstallationLocation { .classify(Bundle.main.bundleURL) }

    var body: some View {
        Group {
            Section("1 · Install one copy") {
                Label(location == .applications ? "Installed in Applications" : "Use the Applications copy for everyday use",
                      systemImage: location == .applications ? "checkmark.circle.fill" : "folder")
                Text("Drag NotchHarbor from the disk image into Applications, eject the disk image, then open NotchHarbor from Applications before granting permissions.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Show this copy") { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
                    Button("Open Applications") { NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications", isDirectory: true)) }
                }
            }
            Section("2 · Keyboard controls") {
                Label(accessibilityGranted ? "Accessibility allowed" : "Accessibility needed for the keyboard HUD",
                      systemImage: accessibilityGranted ? "checkmark.circle.fill" : "keyboard")
                Text("Allows NotchHarbor to handle volume and brightness keys. Open Accessibility, enable NotchHarbor, and return here. If it is missing, click + and select your Applications copy. macOS may ask you to unlock with Touch ID or your password.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Open Accessibility…") { state.mediaKeys.requestAccess() }
                if accessibilityGranted && !state.mediaKeys.active {
                    Text(state.mediaKeys.status).font(.caption).foregroundStyle(.secondary)
                }
                Text("You can skip this and use normal system keyboard controls.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("3 · Music apps · optional") {
                Text("Connect the player you use, then allow NotchHarbor in the macOS Automation prompt. Browser playback uses macOS Now Playing automatically.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Connect Spotify") { state.music.connect(.spotify) }.disabled(!state.preferences.musicEnabled)
                    Button("Connect Apple Music") { state.music.connect(.appleMusic) }.disabled(!state.preferences.musicEnabled)
                }
                ForEach([MusicSource.spotify, .appleMusic]) { source in
                    if let message = state.music.messages[source] { Text(message).font(.caption).foregroundStyle(.secondary) }
                }
                Button("Open Automation…") { openPrivacy("Privacy_Automation") }
            }
            Section("4 · Live audio bars · optional") {
                if !visualizer.isSupported {
                    Text("Requires macOS 14.2+. Normal music controls still work.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Samples system output only while the music visualizer is visible. No microphone, screen images, recordings or audio uploads are involved.")
                        .font(.caption).foregroundStyle(.secondary)
                    if visualizer.setupRequired {
                        Button("Enable live visualizer") { visualizer.retry() }
                        Text("macOS asks for System Audio Recording Only when a playing track next appears or you hover its playback slider. You can leave this off.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Label(visualizer.hasCaptured ? "Audio capture has worked on this Mac" : "Enabled · waiting for playback", systemImage: "waveform")
                        Button("Open audio permissions…") { visualizer.openAudioSettings() }
                        if visualizer.needsRetry { Button("Retry visualizer") { visualizer.retry() } }
                    }
                    if let error = visualizer.error { Text(error).font(.caption).foregroundStyle(.secondary) }
                    Text("If macOS offers Quit & Reopen after approval, use it once, then open the same Applications copy. If access was denied, enable NotchHarbor in Privacy & Security and choose Retry visualizer.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                Text("Permissions are always your choice. NotchHarbor never enables them for you or resets macOS privacy settings. Bluetooth is optional under Activities; Codex uses your existing local sign-in.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Recheck permissions") { refresh() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
        .onAppear { refresh() }
    }

    private func refresh() {
        accessibilityGranted = AXIsProcessTrusted()
        state.mediaKeys.recover()
        state.music.refresh()
    }
    private func openPrivacy(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
    }
}
