import Foundation
import CoreServices

/// Fallback for desktop builds without a shared app-server socket. Observes only
/// file metadata: no session contents, prompts, responses, or token data are read.
@MainActor final class CodexSessionActivity {
    private var stream: FSEventStreamRef?
    private var root = URL(fileURLWithPath: "/")
    private var fingerprints: [String: String] = [:]
    var onActivity: ((Date) -> Void)?

    func start(root: URL) {
        stop()
        self.root = root.standardizedFileURL
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, context, count, paths, flags, _ in
            guard let context else { return }
            let observer = Unmanaged<CodexSessionActivity>.fromOpaque(context).takeUnretainedValue()
            let strings = unsafeBitCast(paths, to: NSArray.self)
            MainActor.assumeIsolated {
                for index in 0..<min(count, 512) {
                    let changed = flags[index] & FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified | kFSEventStreamEventFlagItemCreated) != 0
                    guard changed, let path = strings[index] as? String else { continue }
                    observer.observe(URL(fileURLWithPath: path))
                }
            }
        }
        guard let stream = FSEventStreamCreate(nil, callback, &context, [self.root.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.2,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)) else { return }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, .main)
        if !FSEventStreamStart(stream) { stop(); return }
        // Catch a run already writing at launch; never replay old session history.
        let now = Date()
        let calendar = Calendar(identifier: .gregorian)
        for offset in [0, -1] {
            guard let date = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            let folder = self.root.appendingPathComponent(String(format: "%04d/%02d/%02d", parts.year!, parts.month!, parts.day!))
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for file in files { observe(file, now: now) }
        }
    }

    // Internal to allow metadata-only fixture tests without relying on FSEvents timing.
    func observe(_ file: URL, now: Date = Date()) {
        let path = file.standardizedFileURL.path
        guard stream != nil, path.hasPrefix(root.path + "/"), file.pathExtension == "jsonl",
              let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              let modified = values.contentModificationDate, let size = values.fileSize, size > 0,
              (-2...10).contains(now.timeIntervalSince(modified)) else { return }
        let fingerprint = "\(size):\(modified.timeIntervalSince1970)"
        guard fingerprints[path] != fingerprint else { return }
        if fingerprints.count >= 512 { fingerprints.removeAll(keepingCapacity: true) }
        fingerprints[path] = fingerprint
        onActivity?(min(modified, now))
    }

    func stop() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
        fingerprints.removeAll()
    }
    deinit {
        if let stream { FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream) }
    }
}
