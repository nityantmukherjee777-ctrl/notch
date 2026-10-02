import AppKit
import Combine
import SwiftUI

struct HUDReading: Equatable {
    enum Kind { case volume, brightness }
    var kind: Kind
    var value: Double
    var muted = false
    var title: String { kind == .volume ? (muted ? "Muted" : "Volume") : "Brightness" }
    var symbol: String { kind == .brightness ? "sun.max.fill" : muted ? "speaker.slash.fill" : "speaker.wave.2.fill" }
}

/// Isolates DisplayServices so a macOS change or unsupported monitor disables
/// only brightness. No kernel extensions, display overrides or DDC writes.
@MainActor final class BrightnessService: ObservableObject {
    @Published private(set) var value: Float?
    @Published private(set) var error: String?
    var onChange: ((Float) -> Void)?
    var onUserChange: ((Float) -> Void)?
    private typealias Getter = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias Setter = @convention(c) (UInt32, Float) -> Int32
    private let framework = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    private var getter: Getter?
    private var setter: Setter?
    private var poll: Timer?
    private var enabled = false
    private var display: UInt32 = 0
    init() {
        if let framework {
            if let symbol = dlsym(framework, "DisplayServicesGetBrightness") { getter = unsafeBitCast(symbol, to: Getter.self) }
            if let symbol = dlsym(framework, "DisplayServicesSetBrightness") { setter = unsafeBitCast(symbol, to: Setter.self) }
        }
    }
    func configure(enabled: Bool) {
        guard enabled != self.enabled else { return }
        self.enabled = enabled; poll?.invalidate(); poll = nil
        if enabled {
            refresh()
            poll = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } }
            poll?.tolerance = 0.15
        } else { value = nil }
    }
    func refresh() {
        guard enabled else { return }
        let screen = NSScreen.screens.first(where: { CGDisplayIsBuiltin($0.displayID) != 0 }) ?? NSScreen.main
        let id = screen?.displayID ?? 0
        var reading: Float = 0
        guard id != 0, let getter, setter != nil, getter(id, &reading) == 0, reading.isFinite else {
            if value != nil { value = nil }
            return
        }
        reading = min(1, max(0, reading))
        let old = value, sameDisplay = id == display
        display = id
        if old == nil || abs((old ?? 0) - reading) > 0.008 {
            value = reading
            if old != nil && sameDisplay { onChange?(reading) }
        }
    }
    func set(_ requested: Float) {
        guard requested.isFinite, value != nil, let setter else { return }
        let clamped = min(1, max(0.05, requested))
        if setter(display, clamped) == 0 { value = clamped; error = nil; onUserChange?(clamped) }
        else { error = "This display doesn’t support brightness control." }
    }
}

struct HUDView: View {
    var reading: HUDReading
    var notchWidth: CGFloat
    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: reading.symbol).font(.system(size: 11))
                Text(reading.title).font(.system(size: 10, weight: .semibold))
            }.frame(width: 105, alignment: .leading)
            Color.clear.frame(width: notchWidth - 14)
            HStack(spacing: 8) {
                GeometryReader { proxy in
                    Capsule().fill(.white.opacity(0.2))
                        .overlay(alignment: .leading) {
                            Capsule().fill(.white).frame(width: proxy.size.width * min(1, max(0, reading.value)))
                        }
                }.frame(width: 53, height: 4)
                Text("\(Int((reading.value * 100).rounded()))").font(.system(size: 10, weight: .medium)).monospacedDigit().frame(width: 22, alignment: .trailing)
            }.frame(width: 105, alignment: .trailing)
        }.accessibilityElement(children: .ignore).accessibilityLabel("\(reading.title) \(Int(reading.value * 100)) percent")
    }
}

/// Keeps feedback visible without resizing or replacing the currently open tool.
struct ExpandedHUDView: View {
    var reading: HUDReading
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: reading.symbol).frame(width: 16)
            Text(reading.title).frame(width: 66, alignment: .leading)
            GeometryReader { proxy in
                Capsule().fill(.white.opacity(0.12))
                    .overlay(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.88))
                            .frame(width: proxy.size.width * min(1, max(0, reading.value)))
                    }
            }.frame(height: 4)
            Text("\(Int((reading.value * 100).rounded()))%")
                .monospacedDigit().frame(width: 34, alignment: .trailing)
        }.font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.75))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(reading.title) \(Int(reading.value * 100)) percent")
    }
}
