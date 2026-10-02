import Foundation
import CoreFoundation

/// A current connected-device snapshot, never a cached Bluetooth preference.
struct BluetoothBatteryReading: Equatable {
    let left: Int?
    let right: Int?
    let main: Int?
    let caseCharge: Int?

    /// Use the lower earbud so the single ring does not overstate listening charge.
    var percentage: Int? { [left, right].compactMap { $0 }.min() ?? main }

    var description: String {
        var parts: [String] = []
        if let left { parts.append("Left \(left)%") }
        if let right { parts.append("Right \(right)%") }
        if left == nil, right == nil, let main { parts.append("Battery \(main)%") }
        if let caseCharge { parts.append("Case \(caseCharge)%") }
        return parts.joined(separator: " · ")
    }

    static func parse(_ data: Data, address: String) -> Self? {
        guard data.count <= 524_288, let target = normalizedAddress(address),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = root["SPBluetoothDataType"] as? [[String: Any]] else { return nil }
        for controller in controllers {
            // Disconnected devices can have historical levels. Never use them.
            guard let groups = controller["device_connected"] as? [[String: Any]] else { continue }
            for group in groups {
                for value in group.values {
                    guard let fields = value as? [String: Any],
                          let rawAddress = fields["device_address"] as? String,
                          normalizedAddress(rawAddress) == target else { continue }
                    let reading = Self(
                        left: percent(fields["device_batteryLevelLeft"] ?? fields["Left Battery Level"]),
                        right: percent(fields["device_batteryLevelRight"] ?? fields["Right Battery Level"]),
                        main: percent(fields["device_batteryLevelMain"] ?? fields["Battery Level"]),
                        caseCharge: percent(fields["device_batteryLevelCase"] ?? fields["Case Battery Level"]))
                    if reading.percentage != nil { return reading }
                }
            }
        }
        return nil
    }

    private static func normalizedAddress(_ value: String) -> String? {
        let cleaned = value.replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "").lowercased()
        guard cleaned.count == 12, cleaned.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { return nil }
        return cleaned
    }

    private static func percent(_ value: Any?) -> Int? {
        let number: Double?
        if let value = value as? String {
            let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
            number = Double(text.hasSuffix("%") ? String(text.dropLast()).trimmingCharacters(in: .whitespaces) : text)
        } else if let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() {
            number = value.doubleValue
        } else { number = nil }
        guard let number, number.isFinite, (0...100).contains(number), number.rounded() == number else { return nil }
        return Int(number)
    }
}

/// Event-only, bounded invocation of Apple's System Information tool. No idle
/// polling, private selectors, BLE scans, persisted snapshots, or shell parsing.
@MainActor final class BluetoothBatteryReader {
    private var process: Process?
    private var output: FileHandle?
    private var buffer = Data()
    private var timeout: Task<Void, Never>?
    private var generation = UUID()
    private var exited = false
    private var outputEnded = false
    private var succeeded = false
    private var completion: ((Data?) -> Void)?

    func read(completion: @escaping (Data?) -> Void) {
        stop()
        self.completion = completion
        let epoch = generation
        let child = Process(), pipe = Pipe()
        child.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        child.arguments = ["SPBluetoothDataType", "-json"]
        child.standardInput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        child.standardOutput = pipe
        output = pipe.fileHandleForReading
        output?.readabilityHandler = { [weak self] handle in
            let data = (try? handle.read(upToCount: 16_384)) ?? Data()
            if data.isEmpty { handle.readabilityHandler = nil }
            Task { @MainActor in self?.receive(data, epoch: epoch) }
        }
        child.terminationHandler = { [weak self] child in
            let success = child.terminationStatus == 0
            Task { @MainActor in
                guard let self, self.generation == epoch else { return }
                self.exited = true; self.succeeded = success; self.finishIfReady()
            }
        }
        process = child
        do { try child.run() } catch { finish(nil); return }
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self, self.generation == epoch else { return }
            self.finish(nil)
        }
    }

    func stop() {
        generation = UUID(); timeout?.cancel(); timeout = nil
        output?.readabilityHandler = nil; output = nil
        if let process, process.isRunning { process.terminate() }
        process = nil; completion = nil; buffer = Data()
        exited = false; outputEnded = false; succeeded = false
    }

    private func receive(_ data: Data, epoch: UUID) {
        guard generation == epoch else { return }
        guard buffer.count + data.count <= 524_288 else { finish(nil); return }
        buffer.append(data)
        if data.isEmpty { outputEnded = true }
        finishIfReady()
    }

    private func finishIfReady() {
        guard exited, outputEnded else { return }
        finish(succeeded ? buffer : nil)
    }

    private func finish(_ data: Data?) {
        let callback = completion
        stop()
        callback?(data)
    }
}
