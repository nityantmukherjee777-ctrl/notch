import AppKit

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let background = NSBezierPath(roundedRect: NSRect(x: 52, y: 52, width: 920, height: 920), xRadius: 208, yRadius: 208)
        NSGradient(starting: NSColor(white: 0.16, alpha: 1), ending: NSColor(white: 0.035, alpha: 1))!.draw(in: background, angle: 90)
        NSColor(white: 1, alpha: 0.12).setStroke(); background.lineWidth = 3; background.stroke()
        let notch = NSBezierPath()
        notch.move(to: CGPoint(x: 233, y: 755)); notch.line(to: CGPoint(x: 791, y: 755))
        notch.line(to: CGPoint(x: 791, y: 550))
        notch.curve(to: CGPoint(x: 685, y: 445), controlPoint1: CGPoint(x: 791, y: 480), controlPoint2: CGPoint(x: 754, y: 445))
        notch.line(to: CGPoint(x: 339, y: 445))
        notch.curve(to: CGPoint(x: 233, y: 550), controlPoint1: CGPoint(x: 270, y: 445), controlPoint2: CGPoint(x: 233, y: 480))
        notch.close(); NSColor.black.setFill(); notch.fill()
        NSColor(red: 0.64, green: 0.91, blue: 0.77, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 410, y: 284, width: 204, height: 66), xRadius: 33, yRadius: 33).fill()
        NSColor(white: 1, alpha: 0.28).setFill()
        NSBezierPath(ovalIn: NSRect(x: 649, y: 284, width: 66, height: 66)).fill()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let url = directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
    }
}

// ICNS accepts PNG representations directly; this also works without iconutil's UI service.
func length(_ value: Int) -> Data {
    var bigEndian = UInt32(value).bigEndian
    return withUnsafeBytes(of: &bigEndian) { Data($0) }
}
var chunks = Data()
for (type, file) in [("icp4", "icon_16x16.png"), ("icp5", "icon_32x32.png"), ("icp6", "icon_32x32@2x.png"), ("ic07", "icon_128x128.png"), ("ic08", "icon_256x256.png"), ("ic09", "icon_512x512.png"), ("ic10", "icon_512x512@2x.png")] {
    let png = try Data(contentsOf: directory.appendingPathComponent(file))
    chunks.append(Data(type.utf8)); chunks.append(length(png.count + 8)); chunks.append(png)
}
try (Data("icns".utf8) + length(chunks.count + 8) + chunks).write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
