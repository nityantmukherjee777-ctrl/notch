import AppKit

/// The private macOS integration is isolated here. The bundled BSD adapter is
/// built from source; it exposes the system Now Playing session, not browser history.
@MainActor final class SystemMediaService {
    var onUpdate: (([String: Any]?) -> Void)?
    var onError: ((String) -> Void)?
    private var process: Process?
    private var output: FileHandle?
    private var errors: FileHandle?
    private var buffer = Data()
    private var generation = UUID()
    private var enabled = false
    private var retry: Task<Void, Never>?
    private var commands: [UUID: Process] = [:]
    private var baseArguments: [String]? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let script = resources.appendingPathComponent("mediaremote-adapter.pl").path
        let framework = Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/MediaRemoteAdapter.framework").path
        guard FileManager.default.fileExists(atPath: script), FileManager.default.fileExists(atPath: framework) else { return nil }
        return [script, framework]
    }
    func start() {
        guard !enabled else { return }
        enabled = true; connect()
    }
    func stop() {
        enabled = false; retry?.cancel(); retry = nil; generation = UUID()
        output?.readabilityHandler = nil; errors?.readabilityHandler = nil
        if let process, process.isRunning { process.terminate() }
        for child in commands.values where child.isRunning { child.terminate() }
        commands.removeAll(); process = nil; output = nil; errors = nil; buffer = Data()
    }
    private func connect() {
        guard enabled, let arguments = baseArguments else { onError?("Browser media helper is missing. Rebuild Notch."); return }
        generation = UUID(); let epoch = generation
        let child = Process(), stdout = Pipe(), stderr = Pipe()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        child.arguments = arguments + ["stream", "--no-diff", "--micros", "--debounce=100"]
        child.standardOutput = stdout; child.standardError = stderr; child.standardInput = FileHandle.nullDevice
        output = stdout.fileHandleForReading; errors = stderr.fileHandleForReading
        output?.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            Task { @MainActor in self?.receive(data, epoch: epoch) }
        }
        errors?.readabilityHandler = { handle in if handle.availableData.isEmpty { handle.readabilityHandler = nil } }
        child.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                guard let self, self.enabled, self.generation == epoch else { return }
                self.output?.readabilityHandler = nil; self.errors?.readabilityHandler = nil
                self.process = nil; self.buffer = Data(); self.onUpdate?(nil)
                self.onError?("System media disconnected. Reconnecting…")
                self.retry = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(15))
                    guard !Task.isCancelled else { return }
                    self?.connect()
                }
            }
        }
        process = child
        do { try child.run() } catch { process = nil; onError?("Couldn’t start system media. Spotify and Apple Music are still available.") }
    }
    private func receive(_ data: Data, epoch: UUID) {
        guard epoch == generation, enabled else { return }
        buffer.append(data)
        guard buffer.count <= 12_000_000 else { buffer = Data(); onError?("System media returned too much artwork data."); return }
        while let newline = buffer.firstIndex(of: 10) {
            let line = Data(buffer.prefix(upTo: newline)); buffer.removeSubrange(...newline)
            guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any], message["type"] as? String == "data" else { continue }
            onUpdate?(message["payload"] as? [String: Any])
        }
    }
    func command(_ arguments: [String]) {
        guard enabled, let base = baseArguments else { return }
        let child = Process(), id = UUID()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/perl"); child.arguments = base + arguments
        child.standardOutput = FileHandle.nullDevice; child.standardError = FileHandle.nullDevice
        child.terminationHandler = { [weak self] child in
            let status = child.terminationStatus
            Task { @MainActor in
                self?.commands[id] = nil
                if status != 0 { self?.onError?("This media app could not complete the command.") }
            }
        }
        commands[id] = child
        do { try child.run() } catch { commands[id] = nil; onError?("Couldn’t send the media command.") }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            if let child = self?.commands[id], child.isRunning { child.terminate() }
        }
    }
}
