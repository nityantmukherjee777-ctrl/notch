import AppKit
import SwiftUI

private enum DeviceArt {
    static let earbuds = Bundle.main.url(forResource: "DeviceEarbuds", withExtension: "png").flatMap(NSImage.init(contentsOf:))
    static let headphones = Bundle.main.url(forResource: "DeviceHeadphones", withExtension: "png").flatMap(NSImage.init(contentsOf:))
}

/// A connection moment inside the existing compact notch. It never creates
/// another window or changes the notch's physical shape.
struct BluetoothConnectionIndicator: View {
    let device: ConnectedDevice
    let notchWidth: CGFloat
    let wingWidth: CGFloat
    let height: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 0) {
            artwork
                .frame(width: wingWidth, height: height)
                .scaleEffect(appeared || reduceMotion ? 1 : 0.92)
                .offset(y: appeared || reduceMotion ? 0 : 2)
                .opacity(appeared || reduceMotion ? 1 : 0)
            Color.clear.frame(width: notchWidth)
            batteryIndicator
                .frame(width: wingWidth, height: height)
        }
        .padding(.horizontal, 8)
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(device.name) connected by Bluetooth")
        .accessibilityValue(device.battery?.description ?? "Battery unavailable")
        .help(device.statusDescription)
        .onAppear {
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.40, extraBounce: 0)) { appeared = true }
        }
    }

    @ViewBuilder private var artwork: some View {
        if let image = device.kind == .airPods || device.kind == .earbuds ? DeviceArt.earbuds : device.kind == .headphones ? DeviceArt.headphones : nil {
            Image(nsImage: image).resizable().scaledToFit()
                .frame(width: 32, height: 32)
                // The earbuds render includes transparent canvas padding.
                // Frame its actual silhouette at a quiet 21pt height.
                .scaleEffect(device.kind == .headphones ? 1 : 1.4)
                .frame(width: 36, height: 28).clipped()
        } else {
            Image(systemName: device.kind.symbol)
                .font(.system(size: 21, weight: .light))
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    @ViewBuilder private var batteryIndicator: some View {
        if let percentage = device.battery?.percentage {
        ZStack {
            Circle().stroke(batteryColor(percentage).opacity(0.24), lineWidth: 2.2)
            Circle().trim(from: 0, to: appeared || reduceMotion ? CGFloat(percentage) / 100 : 0)
                .stroke(batteryColor(percentage),
                        style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 21, height: 21)
        .animation(reduceMotion ? nil : .smooth(duration: 0.4, extraBounce: 0), value: percentage)
        .accessibilityHidden(true)
        } else {
            // Unknown is distinct from zero or full. Do not draw a battery arc.
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))
                .frame(width: 21, height: 21)
                .accessibilityHidden(true)
        }
    }

    private func batteryColor(_ percentage: Int) -> Color {
        percentage <= 10 ? Color(red: 0.98, green: 0.30, blue: 0.30)
            : percentage <= 20 ? Color(red: 0.98, green: 0.73, blue: 0.25)
            : Color(red: 0.30, green: 0.86, blue: 0.46)
    }
}
