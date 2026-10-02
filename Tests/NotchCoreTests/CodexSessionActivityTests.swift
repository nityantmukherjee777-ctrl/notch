import Foundation
import Testing
@testable import Notch

@Suite(.serialized) @MainActor struct CodexSessionActivityTests {
    @Test func sessionWritesArrivePromptlyAndStopWhenDisabled() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("notch-activity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let observer = CodexSessionActivity()
        defer { observer.stop() }
        var observations = 0
        observer.onActivity = { _ in observations += 1 }
        observer.start(root: root)
        let file = root.appendingPathComponent("session.jsonl")
        // Deliberately not valid JSON: observation must never parse the contents.
        try Data("opaque fixture".utf8).write(to: file)
        for _ in 0..<40 {
            if observations > 0 { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(observations > 0, "Local session writes should be detected within two seconds")
        let count = observations
        observer.observe(file)
        #expect(observations == count, "Duplicate file events must not renew activity")
        observer.stop()
        try Data("different opaque fixture".utf8).write(to: file)
        try await Task.sleep(for: .milliseconds(350))
        observer.observe(file)
        #expect(observations == count, "Disabled tracking must stop file observation")
    }

    @Test func oldFilesUnrelatedFilesAndSymlinksDoNotCount() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("notch-activity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let observer = CodexSessionActivity()
        defer { observer.stop() }
        var observations = 0
        observer.onActivity = { _ in observations += 1 }
        observer.start(root: root)
        let old = root.appendingPathComponent("old.jsonl")
        try Data("old".utf8).write(to: old)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-30)], ofItemAtPath: old.path)
        observer.observe(old)
        let unrelated = root.appendingPathComponent("settings.json")
        try Data("settings".utf8).write(to: unrelated)
        observer.observe(unrelated)
        let link = root.appendingPathComponent("link.jsonl")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: unrelated)
        observer.observe(link)
        #expect(observations == 0)
        let recent = root.appendingPathComponent("recent.jsonl")
        try Data("new".utf8).write(to: recent)
        observer.observe(recent)
        #expect(observations == 1)
    }
}
