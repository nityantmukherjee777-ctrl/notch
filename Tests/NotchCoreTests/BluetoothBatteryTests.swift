import Foundation
import Testing
@testable import Notch

@Suite struct BluetoothBatteryTests {
    private let address = "AA-BB-CC-DD-EE-FF"

    private func snapshot(_ fields: [String: Any], connected: Bool = true) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["SPBluetoothDataType": [
            [connected ? "device_connected" : "device_not_connected": [
                ["Same device name": ["device_address": "11:22:33:44:55:66", "device_batteryLevelMain": "100%"]],
                ["Same device name": fields.merging(["device_address": address]) { first, _ in first }]
            ]]
        ]])
    }

    @Test func matchesAddressAcrossGroupsAndUsesLowerEarbud() throws {
        let data = try snapshot(["device_batteryLevelLeft": "76%", "device_batteryLevelRight": "64%", "device_batteryLevelCase": "99%"])
        let reading = BluetoothBatteryReading.parse(data, address: "aa:bb:cc:dd:ee:ff")
        #expect(reading?.percentage == 64)
        #expect(reading?.description == "Left 76% · Right 64% · Case 99%")
        #expect(BluetoothBatteryReading.parse(data, address: "invalid") == nil)
    }

    @Test func genuineZeroAndFullAreDistinctFromMissingAndInvalid() throws {
        for (raw, expected) in [("0%", 0), ("100%", 100), (" 25% ", 25)] {
            let data = try snapshot(["device_batteryLevelMain": raw])
            #expect(BluetoothBatteryReading.parse(data, address: address)?.percentage == expected)
        }
        let zero = try snapshot(["device_batteryLevelLeft": 0, "device_batteryLevelRight": 50])
        #expect(BluetoothBatteryReading.parse(zero, address: address)?.percentage == 0)
        for invalid: Any in [true, -1, 101, 12.5, "unknown", "NaN", NSNull()] {
            let data = try snapshot(["device_batteryLevelMain": invalid])
            #expect(BluetoothBatteryReading.parse(data, address: address) == nil)
        }
    }

    @Test func disconnectedAndCaseOnlySnapshotsNeverBecomeListeningCharge() throws {
        let disconnected = try snapshot(["device_batteryLevelMain": "90%"], connected: false)
        #expect(BluetoothBatteryReading.parse(disconnected, address: address) == nil)
        let caseOnly = try snapshot(["device_batteryLevelCase": "99%"])
        #expect(BluetoothBatteryReading.parse(caseOnly, address: address) == nil)
        let absent = try snapshot([:])
        #expect(BluetoothBatteryReading.parse(absent, address: address) == nil)
        #expect(BluetoothBatteryReading.parse(Data("broken".utf8), address: address) == nil)
        #expect(BluetoothBatteryReading.parse(Data(repeating: 32, count: 524_289), address: address) == nil)
    }

    @Test func acceptsSingleBudAndMainChargeWithoutFabricatingPartner() throws {
        let single = try snapshot(["Left Battery Level": "42%", "device_batteryLevelMain": "80%"])
        let reading = BluetoothBatteryReading.parse(single, address: address)
        #expect(reading?.percentage == 42)
        #expect(reading?.right == nil)
        let main = try snapshot(["device_batteryLevelMain": 33])
        #expect(BluetoothBatteryReading.parse(main, address: address)?.description == "Battery 33%")
    }
}
