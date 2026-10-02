import AppKit
import Combine
import NotchCore

@MainActor final class CodexService: ObservableObject {
    @Published private(set) var snapshot: QuotaSnapshot?
    @Published private(set) var status = "Tracking is off"
    @Published private(set) var fetching = false
    @Published private(set) var connected = false
    @Published private(set) var lastError: String?
    @Published private(set) var bubbleVisible = false
    private var activity = CodexActivity()
    private let sessionActivity = CodexSessionActivity()
    private var activityExpiry: Task<Void, Never>?
    private var enabled = false
    private var binaryPath = ""
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var errors: FileHandle?
    private var buffer = Data()
    private var generation = UUID()
    private var ready = false
    private var usingProxy = true
    private var requestID = 1
    private var pendingID: Int?
    private var refreshTimer: Timer?
    private var timeout: Task<Void, Never>?
    private var resetRefresh: Task<Void, Never>?
    var resolvedBinary: String? {
        let apps = ["com.openai.codex", "com.openai.chat"].compactMap {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
        } + [URL(fileURLWithPath: "/Applications/ChatGPT.app"), URL(fileURLWithPath: "/Applications/Codex.app")]
        let bundled = apps.flatMap { app in
            ["Contents/Resources/codex-cli/bin/codex", "Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex", "Contents/Resources/codex"].map { app.appendingPathComponent($0).path }
        }
        return CodexExecutable.firstAvailable(custom: binaryPath, bundled: bundled)
    }
    func updateActivityVisibility(at now: Date = Date()) {
        let running = NSWorkspace.shared.runningApplications.contains {
            ["com.openai.codex", "com.openai.chat"].contains($0.bundleIdentifier ?? "")
        }
        let visible = enabled && activity.isVisible(at: now, providerRunning: running)
        if bubbleVisible != visible { bubbleVisible = visible }
    }
    private func recordActivity(at date: Date = Date()) {
        guard enabled else { return }
        // Coalesce streaming writes; visibility appears on the first event.
        if let last = activity.lastConsumption, date.timeIntervalSince(last) < 1 { return }
        activity.recordConsumption(at: date)
        scheduleActivityExpiry()
    }
    private func scheduleActivityExpiry() {
        activityExpiry?.cancel()
        updateActivityVisibility()
        guard let last = activity.lastConsumption else { return }
        let delay = max(0, last.addingTimeInterval(CodexActivity.inactivityInterval).timeIntervalSinceNow)
        activityExpiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.updateActivityVisibility()
        }
    }

    func configure(enabled: Bool, path: String) {
        guard self.enabled != enabled || binaryPath != path else { return }
        stop(); self.enabled = enabled; binaryPath = path
        if enabled {
            sessionActivity.onActivity = { [weak self] date in self?.recordActivity(at: date) }
            let home = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
            sessionActivity.start(root: home.appendingPathComponent("sessions"))
            status = "Connecting to Codex…"; refresh()
            refreshTimer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } }
            refreshTimer?.tolerance = 5
            if let refreshTimer { RunLoop.main.add(refreshTimer, forMode: .common) }
        }
    }
    func stop() {
        sessionActivity.stop(); sessionActivity.onActivity = nil
        enabled = false; refreshTimer?.invalidate(); refreshTimer = nil; resetRefresh?.cancel(); resetRefresh = nil
        activityExpiry?.cancel(); activityExpiry = nil; activity = CodexActivity(); bubbleVisible = false
        disconnect(); snapshot = nil; status = "Tracking is off"; lastError = nil
    }
    private func disconnect() {
        generation = UUID(); timeout?.cancel(); timeout = nil; pendingID = nil
        output?.readabilityHandler = nil; errors?.readabilityHandler = nil
        try? input?.close(); input = nil
        if let process, process.isRunning { process.terminate() }
        process = nil; output = nil; errors = nil; buffer.removeAll(); ready = false; connected = false; fetching = false
    }
    func refresh() {
        updateActivityVisibility()
        guard enabled, !fetching else { return }
        if process?.isRunning == true && ready { requestLimits() }
        else if process?.isRunning != true { connect(proxy: true) }
    }
    private func connect(proxy: Bool) {
        guard enabled else { return }
        guard let path = resolvedBinary else {
            status = "Codex not found"; lastError = "Install Codex or choose its executable in Settings → Tracked Apps."; return
        }
        disconnect(); usingProxy = proxy; let epoch = generation
        let child = Process(), stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        child.executableURL = URL(fileURLWithPath: path)
        child.arguments = proxy ? ["app-server", "proxy"] : ["app-server", "--listen", "stdio://"]
        child.standardInput = stdin; child.standardOutput = stdout; child.standardError = stderr
        child.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        input = stdin.fileHandleForWriting; output = stdout.fileHandleForReading; errors = stderr.fileHandleForReading
        output?.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            Task { @MainActor in self?.receive(data, epoch: epoch) }
        }
        // Drain diagnostics without storing or displaying potentially sensitive provider output.
        errors?.readabilityHandler = { handle in if handle.availableData.isEmpty { handle.readabilityHandler = nil } }
        child.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == epoch, self.enabled else { return }
                let fallback = self.usingProxy && !self.ready
                self.disconnect()
                if fallback { self.connect(proxy: false) }
                else { self.status = "Codex disconnected"; self.lastError = "Open Codex and retry. Tracking will reconnect automatically." }
            }
        }
        process = child; fetching = true; status = "Connecting to Codex…"
        do {
            try child.run()
            send(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "notch_usage", "title": "NotchHarbor", "version": "1.0.0"]]])
            armTimeout(epoch: epoch)
        } catch {
            disconnect(); status = "Couldn’t connect"; lastError = "The selected Codex executable could not be started."
        }
    }
    private func send(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        do { try input?.write(contentsOf: data + Data([10])) }
        catch { lastError = "The connection to Codex was interrupted." }
    }
    private func requestLimits() {
        requestID += 1; if requestID == 1 { requestID += 1 }
        pendingID = requestID; fetching = true; status = snapshot == nil ? "Reading usage…" : "Updating…"
        send(["id": requestID, "method": "account/rateLimits/read"])
        armTimeout(epoch: generation)
    }
    private func armTimeout(epoch: UUID) {
        timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled, let self, self.generation == epoch, self.enabled else { return }
            let fallback = self.usingProxy && !self.ready
            self.disconnect()
            if fallback { self.connect(proxy: false) }
            else { self.status = "Connection timed out"; self.lastError = "Check your connection and sign in to Codex, then retry." }
        }
    }
    private func receive(_ chunk: Data, epoch: UUID) {
        guard generation == epoch, enabled else { return }
        buffer.append(chunk)
        guard buffer.count <= 2_000_000 else { disconnect(); status = "Invalid response"; lastError = "Codex returned an oversized response."; return }
        while let newline = buffer.firstIndex(of: 10) {
            let line = buffer.prefix(upTo: newline); buffer.removeSubrange(...newline)
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if object["id"] as? Int == 1 {
                guard object["error"] == nil else { disconnect(); status = "Incompatible Codex version"; lastError = "Update Codex and retry."; return }
                ready = true; connected = true; fetching = false; timeout?.cancel()
                send(["method": "initialized", "params": [:]])
                requestLimits()
            } else if let id = object["id"] as? Int, id == pendingID {
                timeout?.cancel(); fetching = false; pendingID = nil
                if let error = object["error"] as? [String: Any] {
                    let text = (error["message"] as? String ?? "").lowercased()
                    let auth = ["auth", "sign in", "login", "unauthorized", "chatgpt"].contains { text.contains($0) }
                    status = auth ? "Sign in to Codex" : "Usage unavailable"
                    lastError = auth ? "Open Codex and sign in with your ChatGPT account. API-key usage doesn’t provide this subscription quota." : "Codex could not fetch your quota. Retry when your connection is available."
                    snapshot = nil
                } else if let result = object["result"] as? [String: Any] { apply(result) }
            } else if object["method"] as? String == "account/rateLimits/updated", let params = object["params"] as? [String: Any] {
                apply(params)
            } else if object["method"] as? String == "thread/tokenUsage/updated", let params = object["params"] as? [String: Any],
                      let usage = params["tokenUsage"] as? [String: Any], let last = usage["last"] as? [String: Any],
                      let total = last["totalTokens"] as? Int, total > 0 {
                recordActivity()
            } else if object["method"] as? String == "turn/started" {
                recordActivity()
            } else if object["method"] as? String == "thread/status/changed",
                      let params = object["params"] as? [String: Any],
                      let status = params["status"] as? [String: Any], status["type"] as? String == "active",
                      (status["activeFlags"] as? [String] ?? []).isEmpty {
                recordActivity()
            } else if object["method"] as? String == "account/updated" {
                activity = CodexActivity(); scheduleActivityExpiry()
                snapshot = nil; lastError = nil; refresh()
            }
        }
    }
    private func apply(_ object: [String: Any]) {
        let parsed = QuotaSnapshot.parse(object, at: Date())
        if let parsed { activity.observe(parsed) }
        scheduleActivityExpiry()
        snapshot = parsed; lastError = nil
        status = parsed == nil ? "Quota not provided" : "Up to date"
        if parsed == nil { lastError = "This account hasn’t provided a Codex usage window. Missing data is not zero usage." }
        resetRefresh?.cancel()
        if let reset = [parsed?.primary?.resetDate, parsed?.secondary?.resetDate].compactMap({ $0 }).filter({ $0 > Date() }).min() {
            let delay = min(86_400, max(1, reset.timeIntervalSinceNow + 1))
            resetRefresh = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }
}
