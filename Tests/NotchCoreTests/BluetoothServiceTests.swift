import Foundation
import Testing
@testable import Notch

@Suite @MainActor struct BluetoothServiceTests {
    @Test func onlyFreshConnectionEventsShowTheCard() {
        let service = BluetoothService(registerNotifications: false)
        let start = Date(timeIntervalSince1970: 100)
        service.receive(name: "AirPods Pro", address: "one", at: start)
        #expect(service.announcement == nil)
        service.configure(enabled: true)
        service.receive(name: "AirPods Pro", address: "one", at: start)
        let first = service.announcement?.id
        #expect(service.announcement?.kind == .airPods)
        service.receive(name: "AirPods Pro", address: "one", at: start.addingTimeInterval(2))
        #expect(service.announcement?.id == first)
        service.receive(name: "AirPods Pro", address: "one", at: start.addingTimeInterval(9))
        #expect(service.announcement?.id != first)
        service.stop()
        #expect(service.announcement == nil)
        service.receive(name: "AirPods Pro", address: "one", at: start.addingTimeInterval(20))
        #expect(service.announcement == nil)
    }

    @Test func deviceNameIsLocalBoundedAndTypeAppropriate() {
        let service = BluetoothService(registerNotifications: false)
        service.configure(enabled: true)
        service.receive(name: "  AirPods Pro\n" + String(repeating: "x", count: 200), address: "two")
        #expect(service.announcement?.kind == .airPods)
        #expect((service.announcement?.name.count ?? 0) <= 64)
        #expect(!(service.announcement?.name.contains("\n") ?? true))
        #expect(ConnectedDeviceKind.classify("Magic Mouse") == .mouse)
        #expect(ConnectedDeviceKind.classify("Galaxy Buds") == .earbuds)
        #expect(ConnectedDeviceKind.classify("AirPods Max") == .headphones)
        service.stop()
    }

    @Test func ordinaryDevicesStayQuietWithoutReplacingAnAppleConnection() {
        let service = BluetoothService(registerNotifications: false)
        service.configure(enabled: true)
        for name in ["Sony Headphones", "Galaxy Buds", "Magic Mouse", "Magic Keyboard", "Living Room Speaker", "Heartbeats"] {
            service.receive(name: name, address: name)
            #expect(service.announcement == nil)
        }
        service.receive(name: "AirPods Pro", address: "apple")
        let token = service.announcement?.id
        service.receive(name: "Sony Headphones", address: "sony")
        #expect(service.announcement?.id == token)
        service.stop()
    }

    @Test func cachedVendorAndClassRecognizeRenamedHeadsets() {
        #expect(ConnectedDeviceKind.appleAudioKind(name: "My music", vendor: 0x004c, vendorSource: 1, major: 4, minor: 6) == .headphones)
        #expect(ConnectedDeviceKind.appleAudioKind(name: "My music", vendor: 0x05ac, vendorSource: 2, major: 4, minor: 1) == .headphones)
        #expect(ConnectedDeviceKind.appleAudioKind(name: "AirPods Pro", vendor: 0x1234, vendorSource: 1, major: 4, minor: 6) == nil)
        #expect(ConnectedDeviceKind.appleAudioKind(name: "AirPods Keyboard", vendor: 0x004c, vendorSource: 1, major: 5, minor: 1) == nil)
        #expect(ConnectedDeviceKind.appleAudioKind(name: "Apple Speaker", vendor: 0x004c, vendorSource: 1, major: 4, minor: 5) == nil)
        #expect(ConnectedDeviceKind.appleAudioKind(name: "Unknown headphones", major: 4, minor: 6) == nil)
    }

    @Test func brandedFallbackKeepsBeatsFormFactorsAppropriate() {
        #expect(ConnectedDeviceKind.appleAudioKind(name: "AirPods Max") == .headphones)
        #expect(ConnectedDeviceKind.appleAudioKind(name: "Beats Fit Pro") == .earbuds)
        #expect(ConnectedDeviceKind.appleAudioKind(name: "Powerbeats Pro") == .earbuds)
        #expect(ConnectedDeviceKind.appleAudioKind(name: "Beats Studio Pro") == .headphones)
        #expect(ConnectedDeviceKind.appleAudioKind(name: "Beats Pill") == nil)
    }
}
