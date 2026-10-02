import AppKit
import Combine
import IOBluetooth

/// Names are used only for a brief local connection card. No scanning, pairing,
/// device commands, history, or raw Bluetooth address storage is involved.
enum ConnectedDeviceKind: Equatable {
    case airPods, earbuds, headphones, speaker, keyboard, mouse, other

    static func classify(_ name: String) -> Self {
        let value = name.lowercased()
        if value.contains("airpods max") { return .headphones }
        if value.contains("airpod") { return .airPods }
        if value.contains("powerbeats") || value.contains("beats fit") || value.contains("beats flex") || value.contains("beats studio buds") || value.contains("beats solo buds") { return .earbuds }
        if value.contains("earbud") || value.contains("buds") || value.contains("earphone") { return .earbuds }
        if value.contains("headphone") || value.contains("headset") || value.contains("beats") { return .headphones }
        if value.contains("speaker") || value.contains("soundbar") { return .speaker }
        if value.contains("keyboard") { return .keyboard }
        if value.contains("mouse") || value.contains("trackpad") { return .mouse }
        return .other
    }

    /// Prefer the already-cached PnP vendor and device class. A branded-name
    /// fallback is used only when macOS has no conflicting identity metadata.
    /// This is presentation routing, not cryptographic device authentication.
    static func appleAudioKind(name: String, vendor: Int? = nil, vendorSource: Int? = nil,
                               major: Int? = nil, minor: Int? = nil) -> Self? {
        if let major, major != 0, major != 4 { return nil }
        if major == 4, let minor, minor != 0, ![1, 2, 6].contains(minor) { return nil }
        let appleVendor: Bool?
        if let vendor, vendorSource == 1 { appleVendor = vendor == 0x004c }
        else if let vendor, vendorSource == 2 { appleVendor = vendor == 0x05ac }
        else { appleVendor = nil }
        if appleVendor == false { return nil }
        let words = name.lowercased().split { !$0.isLetter && !$0.isNumber }
        // Beats also sells speakers; branding alone must not opt them in.
        if words.contains("pill") || words.contains("speaker") || words.contains("soundbar") { return nil }
        let branded = words.contains("airpods") || words.contains("airpod") || words.contains("beats") || words.contains("powerbeats")
        if branded { return classify(name) }
        // A renamed headset remains eligible, but no exact model is invented.
        if appleVendor == true, major == 4, let minor, [1, 2, 6].contains(minor) { return .headphones }
        return nil
    }

    var symbol: String {
        switch self {
        case .airPods, .earbuds: "earbuds"
        case .headphones: "headphones"
        case .speaker: "hifispeaker.fill"
        case .keyboard: "keyboard.fill"
        case .mouse: "magicmouse.fill"
        case .other: "app.connected.to.app.below.fill"
        }
    }
}

struct ConnectedDevice: Identifiable, Equatable {
    let id: UUID
    let name: String
    let kind: ConnectedDeviceKind
    var battery: BluetoothBatteryReading? = nil

    var statusDescription: String {
        "\(name) connected" + (battery.map { " · \($0.description)" } ?? " · Battery unavailable")
    }
}

@MainActor final class BluetoothService: NSObject, ObservableObject {
    @Published private(set) var announcement: ConnectedDevice?
    @Published private(set) var error: String?
    private var registration: IOBluetoothUserNotification?
    private var enabled = false
    private var lastConnection: [Int: Date] = [:]
    private var expiry: Task<Void, Never>?
    private var batteryRefresh: Task<Void, Never>?
    private let batteryReader = BluetoothBatteryReader()
    private let registerNotifications: Bool

    init(registerNotifications: Bool = true) { self.registerNotifications = registerNotifications; super.init() }

    func configure(enabled: Bool) {
        guard enabled != self.enabled else { return }
        stop()
        self.enabled = enabled
        guard enabled, registerNotifications else { return }
        registration = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(connected(_:from:)))
        if registration == nil { error = "Bluetooth connection alerts are unavailable. Check Bluetooth access in System Settings." }
    }

    func stop() {
        registration?.unregister(); registration = nil
        enabled = false; expiry?.cancel(); expiry = nil
        batteryRefresh?.cancel(); batteryRefresh = nil; batteryReader.stop()
        announcement = nil; lastConnection.removeAll(); error = nil
    }

    @objc private nonisolated func connected(_ notification: IOBluetoothUserNotification, from device: IOBluetoothDevice) {
        // IOBluetooth does not promise a main-thread callback. Transfer only
        // short, value-type metadata to the UI actor.
        let name = device.name ?? "Bluetooth device"
        let address = device.addressString ?? name
        // This public API reads previously queried service records only. It
        // does not initiate discovery, pairing, or a new remote SDP query.
        let record = device.getServiceRecord(for: IOBluetoothSDPUUID(uuid16: UInt16(kBluetoothSDPUUID16ServiceClassPnPInformation.rawValue)))
        let vendor = record?.getAttributeDataElement(UInt16(kBluetoothSDPAttributeDeviceIdentifierVendorID.rawValue))?.getNumberValue()?.intValue
        let vendorSource = record?.getAttributeDataElement(UInt16(kBluetoothSDPAttributeDeviceIdentifierVendorIDSource.rawValue))?.getNumberValue()?.intValue
        let major = Int(device.deviceClassMajor), minor = Int(device.deviceClassMinor)
        DispatchQueue.main.async { [weak self] in
            self?.receive(name: name, address: address, vendor: vendor, vendorSource: vendorSource, major: major, minor: minor)
        }
    }

    /// Also used by event fixtures. Ignores repeated profile connections.
    func receive(name: String, address: String, at now: Date = Date(), vendor: Int? = nil,
                 vendorSource: Int? = nil, major: Int? = nil, minor: Int? = nil) {
        guard enabled else { return }
        let safeName = String(name.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.prefix(64))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let kind = ConnectedDeviceKind.appleAudioKind(name: safeName, vendor: vendor,
            vendorSource: vendorSource, major: major, minor: minor) else { return }
        let identity = (address.isEmpty ? safeName : address).hashValue
        if let previous = lastConnection[identity], now.timeIntervalSince(previous) < 8 { return }
        if lastConnection.count >= 128 { lastConnection.removeAll() }
        lastConnection[identity] = now
        announcement = ConnectedDevice(id: UUID(), name: safeName.isEmpty ? "Bluetooth device" : safeName,
                                       kind: kind)
        expiry?.cancel()
        batteryRefresh?.cancel(); batteryReader.stop()
        let token = announcement?.id
        if registerNotifications, let token {
            scheduleBattery(address: address, token: token, retry: true)
        }
        expiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, let self, self.announcement?.id == token else { return }
            self.announcement = nil
            self.batteryRefresh?.cancel(); self.batteryRefresh = nil; self.batteryReader.stop()
        }
    }

    private func scheduleBattery(address: String, token: UUID, retry: Bool) {
        batteryRefresh = Task { [weak self] in
            // Give the audio profile a moment to publish battery information.
            try? await Task.sleep(for: .milliseconds(retry ? 350 : 650))
            guard !Task.isCancelled, let self, self.enabled, self.announcement?.id == token else { return }
            self.batteryReader.read { [weak self] data in
                guard let self, self.enabled, self.announcement?.id == token else { return }
                if let data, let reading = BluetoothBatteryReading.parse(data, address: address) {
                    self.announcement?.battery = reading
                } else if retry {
                    self.scheduleBattery(address: address, token: token, retry: false)
                }
            }
        }
    }
}
