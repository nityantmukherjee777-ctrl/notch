import AppKit
import ApplicationServices
import Combine
import NotchCore

/// Owns a reversible, in-process event tap for five hardware media keys only.
/// Returning the original event is the default, including unsupported devices.
@MainActor final class MediaKeyService: ObservableObject {
    @Published private(set) var active = false
    @Published private(set) var status = "Accessibility access needed"
    var handle: ((HardwareControl, Double) -> Bool)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var check: Timer?
    private var enabled = false
    private var consumed = Set<Int>()
    func configure(enabled: Bool) {
        guard self.enabled != enabled else { return }
        self.enabled = enabled
        if enabled {
            connect()
            check = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.connect() }
            }
            check?.tolerance = 0.5
            if let check { RunLoop.main.add(check, forMode: .common) }
        } else { stop() }
    }
    /// Session changes may invalidate a tap even though Accessibility remains
    /// granted. Rebuild the connection without asking for permission again.
    func recover() {
        guard enabled else { return }
        disconnect()
        connect()
    }
    func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
        connect()
    }
    private func connect() {
        guard enabled else { return }
        guard AXIsProcessTrusted() else {
            disconnect(); status = "Enable Accessibility to replace the keyboard HUD"; return
        }
        if let tap {
            if CFMachPortIsValid(tap) {
                if !CGEvent.tapIsEnabled(tap: tap) { CGEvent.tapEnable(tap: tap, enable: true) }
                active = CGEvent.tapIsEnabled(tap: tap)
                if active { return }
            }
            disconnect()
        }
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            return MainActor.assumeIsolated {
                Unmanaged<MediaKeyService>.fromOpaque(context).takeUnretainedValue().receive(type, event)
            }
        }
        let context = Unmanaged.passUnretained(self).toOpaque()
        let mask = CGEventMask(1) << 14
        let port = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: callback, userInfo: context)
            ?? CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                options: .defaultTap, eventsOfInterest: mask, callback: callback, userInfo: context)
        guard let port else {
            status = "macOS could not enable keyboard HUD replacement"; return
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            CFMachPortInvalidate(port)
            status = "Keyboard connection unavailable · retrying"; return
        }
        tap = port; self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        active = CGEvent.tapIsEnabled(tap: port)
        status = active ? "Keyboard HUD ready · press a volume or brightness key" : "Keyboard connection unavailable · retrying"
    }
    private func receive(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            consumed.removeAll()
            if let tap, enabled { CGEvent.tapEnable(tap: tap, enable: true) }
            active = tap.map { CFMachPortIsValid($0) && CGEvent.tapIsEnabled(tap: $0) } ?? false
            return Unmanaged.passUnretained(event)
        }
        guard enabled, let native = NSEvent(cgEvent: event), native.type == .systemDefined, native.subtype.rawValue == 8 else { return Unmanaged.passUnretained(event) }
        let code = (native.data1 >> 16) & 0xffff
        let phase = (native.data1 >> 8) & 0xff
        guard let control = HardwareControl(rawValue: code) else { return Unmanaged.passUnretained(event) }
        if phase == 0x0b { return consumed.remove(code) != nil ? nil : Unmanaged.passUnretained(event) }
        guard phase == 0x0a else { return Unmanaged.passUnretained(event) }
        // Preserve modifier shortcuts that open Sound/Displays or target other displays.
        let flags = native.modifierFlags.intersection([.command, .control, .option, .shift])
        guard flags.isEmpty || flags == [.shift] || flags == [.shift, .option] else { return Unmanaged.passUnretained(event) }
        let step = flags.contains(.option) && flags.contains(.shift) ? 1.0 / 64 : 1.0 / 16
        guard handle?(control, step) == true else { consumed.remove(code); return Unmanaged.passUnretained(event) }
        if status != "Receiving volume and brightness keys" { status = "Receiving volume and brightness keys" }
        consumed.insert(code)
        return nil
    }
    private func disconnect() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil; active = false; consumed.removeAll()
    }
    func stop() {
        enabled = false; check?.invalidate(); check = nil; disconnect(); status = "System keyboard HUD is active"
    }
}
