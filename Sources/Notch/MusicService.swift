import AppKit
import Carbon
import Combine

enum MusicSource: String, CaseIterable, Identifiable {
    case spotify, appleMusic, system
    var id: String { rawValue }
    var name: String { self == .spotify ? "Spotify" : self == .appleMusic ? "Apple Music" : "System media" }
    var bundleID: String { self == .spotify ? "com.spotify.client" : self == .appleMusic ? "com.apple.Music" : "" }
}

struct Track: Equatable {
    var source: MusicSource
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var position: Double
    var playing: Bool
    var artworkURL: String
    var remoteBundleID: String? = nil
    var sourceName: String { remoteBundleID.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)?.deletingPathExtension().lastPathComponent } ?? source.name }
    var identity: String { "\(source.rawValue)|\(remoteBundleID ?? "")|\(title)|\(artist)|\(album)" }
    func sanitized() -> Track {
        var copy = self
        copy.duration = Self.safeSeconds(duration)
        copy.position = Self.safeSeconds(position)
        if copy.duration > 0 { copy.position = min(copy.position, copy.duration) }
        copy.title = String(title.prefix(2_000)); copy.artist = String(artist.prefix(2_000)); copy.album = String(album.prefix(2_000))
        return copy
    }
    static func safeSeconds(_ value: Double) -> Double {
        value.isFinite ? min(31_536_000, max(0, value)) : 0
    }
}

private struct MusicResult {
    var track: Track?
    var error: String?
    var permissionNeeded = false
}

@MainActor final class MusicService: ObservableObject {
    @Published private(set) var track: Track?
    @Published private(set) var artwork: NSImage? {
        didSet { artworkAccent = ArtworkAccent.color(for: artwork) }
    }
    @Published private(set) var artworkAccent: NSColor = ArtworkAccent.fallback
    @Published private(set) var messages: [MusicSource: String] = [:]
    @Published private(set) var needsPermission: Set<MusicSource> = []
    @Published var preferredSource: MusicSource? { didSet { chooseTrack(); refresh() } }
    @Published private(set) var availableTracks: [Track] = []
    private let systemMedia = SystemMediaService()
    private var remoteTrack: Track?
    private var remoteArtwork: NSImage?
    private var remoteSampleTime = Date()
    private var remoteBasePosition = 0.0
    var selectedSourceIndex: Int { availableTracks.firstIndex(where: { $0.source == track?.source }) ?? 0 }
    func cycleSource(_ direction: Int) {
        guard availableTracks.count > 1 else { return }
        preferredSource = availableTracks[(selectedSourceIndex + direction + availableTracks.count) % availableTracks.count].source
    }
    init() {
        systemMedia.onUpdate = { [weak self] payload in self?.receiveSystem(payload) }
        systemMedia.onError = { [weak self] error in self?.messages[.system] = error }
    }
    func receiveSystem(_ payload: [String: Any]?) {
        messages[.system] = nil
        guard let payload, let title = payload["title"] as? String, !title.isEmpty,
              let bundle = (payload["parentApplicationBundleIdentifier"] as? String) ?? (payload["bundleIdentifier"] as? String), !bundle.isEmpty else {
            remoteTrack = nil; remoteArtwork = nil; chooseTrack(); return
        }
        func seconds(_ key: String) -> Double {
            guard let number = payload[key] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { return 0 }
            let seconds = max(0, number.doubleValue / 1_000_000)
            return key == "timestampEpochMicros" ? min(253_402_300_799, seconds) : Track.safeSeconds(seconds)
        }
        let elapsed = seconds("elapsedTimeMicros"), timestamp = seconds("timestampEpochMicros")
        let playing = payload["playing"] as? Bool ?? false
        remoteSampleTime = Date()
        remoteBasePosition = elapsed + (playing && timestamp > 0 ? max(0, min(86400, Date().timeIntervalSince1970 - timestamp)) : 0)
        // Keep the provider identity, while remoteBundleID records the system
        // transport. Desktop scripting may return no track even though Now
        // Playing has a valid Spotify or Music session.
        let source = MusicSource.allCases.first { $0 != .system && $0.bundleID == bundle } ?? .system
        remoteTrack = Track(source: source, title: title, artist: payload["artist"] as? String ?? "", album: payload["album"] as? String ?? "",
            duration: seconds("durationMicros"), position: remoteBasePosition, playing: playing, artworkURL: "", remoteBundleID: bundle).sanitized()
        if let base64 = payload["artworkData"] as? String, base64.count < 10_000_000, let data = Data(base64Encoded: base64) { remoteArtwork = SafeArtwork.image(data) }
        else { remoteArtwork = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle).map { NSWorkspace.shared.icon(forFile: $0.path) } }
        if playing { recentPlaying = source }
        chooseTrack()
    }
    func applyDesktopTracks(_ tracks: [MusicSource: Track]) {
        for source in MusicSource.allCases {
            if tracks[source]?.playing == true && previousTracks[source]?.playing != true { recentPlaying = source }
        }
        previousTracks = tracks.mapValues { $0.sanitized() }
        chooseTrack()
    }
    private func chooseTrack() {
        var tracks = previousTracks
        if var remote = remoteTrack {
            remote.position = remoteBasePosition + (remote.playing ? Date().timeIntervalSince(remoteSampleTime) : 0)
            if remote.duration > 0 { remote.position = min(remote.duration, remote.position) }
            // Prefer the dedicated provider when it has a live track, without
            // duplicating it. A playing system session can also replace a
            // paused desktop response until the next scripting poll catches up.
            if tracks[remote.source] == nil || (remote.playing && tracks[remote.source]?.playing != true) {
                tracks[remote.source] = remote
            }
        }
        let available = MusicSource.allCases.compactMap { tracks[$0] }
        if availableTracks != available { availableTracks = available }
        let picked: Track?
        if let preferred = preferredSource, let candidate = tracks[preferred] { picked = candidate }
        else if let recent = recentPlaying, let candidate = tracks[recent], candidate.playing { picked = candidate }
        else { picked = available.first(where: \.playing) ?? available.first }
        if track != picked { track = picked }
        loadArtwork()
    }
    private let queue = DispatchQueue(label: "app.notch.music", qos: .utility)
    private var poll: Timer?
    private var busy = false
    private var enabled = false
    private var expanded = false
    private var generation = UUID()
    private var previousTracks: [MusicSource: Track] = [:]
    private var recentPlaying: MusicSource?
    private var artworkTask: Task<Void, Never>?
    private var artworkIdentity = ""
    private var artworkAttempt = Date.distantPast
    func configure(enabled: Bool) {
        guard enabled != self.enabled else { return }
        self.enabled = enabled; generation = UUID(); busy = false
        poll?.invalidate(); poll = nil
        if enabled { systemMedia.start(); refresh(); schedule() }
        else { systemMedia.stop(); remoteTrack = nil; availableTracks = []; track = nil; artwork = nil; artworkTask?.cancel(); artworkIdentity = ""; messages = [:]; needsPermission = []; previousTracks = [:] }
    }
    func setExpanded(_ value: Bool) { if expanded != value { expanded = value; schedule(); if value { refresh() } } }
    private func schedule() {
        poll?.invalidate(); poll = nil
        guard enabled else { return }
        poll = Timer.scheduledTimer(withTimeInterval: expanded ? 1 : 5, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } }
        poll?.tolerance = expanded ? 0.2 : 1
    }
    func connect(_ source: MusicSource) {
        guard enabled, source != .system else { return }
        if NSRunningApplication.runningApplications(withBundleIdentifier: source.bundleID).isEmpty {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleID) else { messages[source] = "\(source.name) is not installed."; return }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, _ in
                Task { @MainActor in self?.requestPermission(source) }
            }
        } else { requestPermission(source) }
    }
    private func requestPermission(_ source: MusicSource) {
        let epoch = generation
        queue.async { [weak self] in
            let target = NSAppleEventDescriptor(bundleIdentifier: source.bundleID)
            let result = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, true)
            Task { @MainActor in
                guard let self, self.generation == epoch else { return }
                if result != noErr { self.messages[source] = "Allow Notch in System Settings → Privacy & Security → Automation." }
                self.refresh()
            }
        }
    }
    func refresh() {
        guard enabled, !busy else { return }
        let running = MusicSource.allCases.filter { $0 != .system && !NSRunningApplication.runningApplications(withBundleIdentifier: $0.bundleID).isEmpty }
        guard !running.isEmpty else { previousTracks = [:]; chooseTrack(); return }
        busy = true; let epoch = generation
        queue.async { [weak self] in
            var results: [MusicSource: MusicResult] = [:]
            for source in running { results[source] = Self.read(source) }
            Task { @MainActor in
                guard let self, self.generation == epoch else { return }
                self.busy = false
                let tracks = results.compactMapValues(\.track)
                self.applyDesktopTracks(tracks)
                var messages = results.compactMapValues(\.error)
                messages[.system] = self.messages[.system]
                if self.messages != messages { self.messages = messages }
                let needed = Set(results.filter { $0.value.permissionNeeded }.map(\.key))
                if self.needsPermission != needed { self.needsPermission = needed }
                self.chooseTrack()
            }
        }
    }
    private nonisolated static func read(_ source: MusicSource) -> MusicResult {
        let target = NSAppleEventDescriptor(bundleIdentifier: source.bundleID)
        guard AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, false) == noErr else {
            return MusicResult(error: "Connect \(source.name) to show what’s playing.", permissionNeeded: true)
        }
        let duration = source == .spotify ? "((duration of current track) / 1000)" : "(duration of current track)"
        let art = source == .spotify ? "(artwork url of current track)" : "\"\""
        let script = """
        with timeout of 3 seconds
            tell application id "\(source.bundleID)"
                if player state is stopped then return {}
                return {name of current track, artist of current track, album of current track, \(duration), player position, (player state is playing), \(art)}
            end tell
        end timeout
        """
        var error: NSDictionary?
        guard let result = NSAppleScript(source: script)?.executeAndReturnError(&error), error == nil else {
            return MusicResult(error: "\(source.name) isn’t responding. Check Automation access or try again.")
        }
        if result.numberOfItems == 0 { return MusicResult() }
        guard result.numberOfItems >= 7 else {
            return MusicResult(error: "\(source.name) returned incomplete playback information. Using system media when available.")
        }
        func string(_ i: Int) -> String { result.atIndex(i)?.stringValue ?? "" }
        return MusicResult(track: Track(source: source, title: string(1), artist: string(2), album: string(3),
            duration: result.atIndex(4)?.doubleValue ?? 0, position: result.atIndex(5)?.doubleValue ?? 0,
            playing: result.atIndex(6)?.booleanValue ?? false, artworkURL: string(7)))
    }
    func openSourceApp() {
        guard let track else { return }
        let bundleID = track.remoteBundleID ?? track.source.bundleID
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) { NSWorkspace.shared.open(url) }
    }
    func seekRelative(_ seconds: Double) {
        guard let track, track.duration > 0 else { return }
        command("seek", position: min(track.duration, max(0, track.position + seconds)))
    }
    func command(_ action: String, position: Double? = nil) {
        guard let track, enabled else { return }
        if let position, position.isFinite, track.duration > 0 {
            applyOptimisticSeek(min(track.duration, max(0, position)), to: track)
        }
        if track.remoteBundleID != nil {
            if let position, position.isFinite, track.duration > 0 {
                systemMedia.command(["seek", String(Int64(min(track.duration, max(0, position)) * 1_000_000))])
            } else if let command = ["playpause": "2", "next track": "4", "previous track": "5"][action] { systemMedia.command(["send", command]) }
            return
        }
        let allowed = ["playpause", "next track", "previous track"]
        let body: String
        if let position, position.isFinite { body = "set player position to \(min(track.duration, max(0, position)))" }
        else if allowed.contains(action) { body = action } else { return }
        let epoch = generation
        queue.async { [weak self] in
            var error: NSDictionary?
            NSAppleScript(source: "with timeout of 3 seconds\ntell application id \"\(track.source.bundleID)\" to \(body)\nend timeout")?.executeAndReturnError(&error)
            let failed = error != nil
            Task { @MainActor in
                guard let self, self.generation == epoch else { return }
                if failed { self.messages[track.source] = "The playback command could not be completed." }
                self.refresh()
            }
        }
    }
    private func applyOptimisticSeek(_ position: Double, to current: Track) {
        if current.remoteBundleID != nil {
            remoteBasePosition = position
            remoteSampleTime = Date()
            if var remoteTrack, remoteTrack.identity == current.identity {
                remoteTrack.position = position
                self.remoteTrack = remoteTrack
            }
        } else if var cached = previousTracks[current.source], cached.identity == current.identity {
            cached.position = position
            previousTracks[current.source] = cached
        }
        if var visible = track, visible.identity == current.identity {
            visible.position = position
            track = visible
        }
        if let index = availableTracks.firstIndex(where: { $0.identity == current.identity }) {
            availableTracks[index].position = position
        }
    }
    private func loadArtwork() {
        guard let track else { artwork = nil; artworkIdentity = ""; artworkTask?.cancel(); return }
        if track.remoteBundleID != nil {
            artworkTask?.cancel(); artworkTask = nil; artworkIdentity = ""
            if artwork !== remoteArtwork { artwork = remoteArtwork }
            return
        }
        let artworkKey = track.identity + "|" + track.artworkURL
        guard artworkIdentity != artworkKey || (artwork == nil && Date().timeIntervalSince(artworkAttempt) >= 30) else { return }
        artworkIdentity = artworkKey; artworkAttempt = Date(); artwork = nil; artworkTask?.cancel()
        let identity = track.identity, epoch = generation
        if track.source == .spotify, let url = URL(string: track.artworkURL), url.scheme == "https" {
            artworkTask = Task { [weak self] in
                var request = URLRequest(url: url); request.timeoutInterval = 8
                guard let data = try? await BoundedDownload.fetch(request, limit: 8_000_000, hosts: SafeArtwork.hosts), !Task.isCancelled,
                      let image = SafeArtwork.image(data), let self, self.generation == epoch, self.track?.identity == identity else { return }
                self.artwork = image
            }
        } else if track.source == .appleMusic {
            queue.async { [weak self] in
                var error: NSDictionary?
                let result = NSAppleScript(source: "with timeout of 3 seconds\ntell application id \"com.apple.Music\" to get raw data of artwork 1 of current track\nend timeout")?.executeAndReturnError(&error)
                let data = error == nil ? result?.data : nil
                Task { @MainActor in
                    guard let self, self.generation == epoch, self.track?.identity == identity, let data, data.count < 8_000_000 else { return }
                    self.artwork = SafeArtwork.image(data)
                }
            }
        }
    }
}
