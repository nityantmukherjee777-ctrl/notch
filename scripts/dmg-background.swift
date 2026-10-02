import AppKit

let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1400, pixelsHigh: 840, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
bitmap.size = NSSize(width: 700, height: 420)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor(calibratedWhite: 0.965, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: 700, height: 420)).fill()
func text(_ value: String, y: CGFloat, size: CGFloat, color: NSColor, weight: NSFont.Weight = .regular) {
    let style = NSMutableParagraphStyle(); style.alignment = .center
    (value as NSString).draw(in: NSRect(x: 24, y: y, width: 652, height: size * 1.7), withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: style])
}
text("NotchHarbor", y: 342, size: 29, color: .black, weight: .semibold)
text("Drag the app into Applications", y: 310, size: 16, color: NSColor(white: 0.36, alpha: 1))
let arrow = NSBezierPath()
arrow.move(to: CGPoint(x: 316, y: 224)); arrow.line(to: CGPoint(x: 384, y: 224))
arrow.move(to: CGPoint(x: 373, y: 235)); arrow.line(to: CGPoint(x: 384, y: 224)); arrow.line(to: CGPoint(x: 373, y: 213))
arrow.lineWidth = 2.5; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
NSColor(white: 0.42, alpha: 1).setStroke(); arrow.stroke()
text("Then eject this disk and open the installed app.", y: 131, size: 13, color: NSColor(white: 0.36, alpha: 1))
text("The Setup page guides you through optional permissions.", y: 22, size: 12, color: NSColor(white: 0.42, alpha: 1))
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .tiff, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
