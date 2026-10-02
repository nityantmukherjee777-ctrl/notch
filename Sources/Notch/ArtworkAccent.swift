import AppKit

/// A small, bounded artwork sample so the compact meter stays legible on black.
enum ArtworkAccent {
    static let fallback = NSColor(calibratedWhite: 0.64, alpha: 1)

    static func color(for image: NSImage?) -> NSColor {
        guard let image,
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 24, pixelsHigh: 24,
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                            isPlanar: false, colorSpaceName: .deviceRGB,
                                            bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return fallback }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: 24, height: 24),
                   from: .zero, operation: .copy, fraction: 1)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        var darkCount = 0, visibleCount = 0
        var bins = [(weight: CGFloat, hue: CGFloat, saturation: CGFloat, brightness: CGFloat)](
            repeating: (0, 0, 0, 0), count: 12)
        for y in 0..<24 {
            for x in 0..<24 {
                guard let pixel = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), pixel.alphaComponent > 0.3 else { continue }
                visibleCount += 1
                var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
                pixel.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
                if brightness < 0.23 { darkCount += 1 }
                guard brightness >= 0.23, saturation >= 0.18 else { continue }
                let index = min(11, Int(hue * 12))
                let weight = saturation * sqrt(brightness)
                bins[index].weight += weight
                bins[index].hue += hue * weight
                bins[index].saturation += saturation * weight
                bins[index].brightness += brightness * weight
            }
        }
        // A predominantly black cover should read as gray, even if its small
        // lettering or a highlight is saturated.
        guard visibleCount > 0, Double(darkCount) / Double(visibleCount) < 0.60,
              let winner = bins.max(by: { $0.weight < $1.weight }), winner.weight > 5 else { return fallback }
        return NSColor(calibratedHue: winner.hue / winner.weight,
                       saturation: max(0.48, min(0.9, winner.saturation / winner.weight)),
                       brightness: max(0.62, min(0.95, winner.brightness / winner.weight)), alpha: 1)
    }
}
