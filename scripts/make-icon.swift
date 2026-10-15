// Renders the app icon. Usage: swift scripts/make-icon.swift && iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
import AppKit

let output = "build/AppIcon.iconset"
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)

let sizes: [(name: String, pixels: Int)] = [
    ("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
    ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024),
]

for (name, pixels) in sizes {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Body follows the macOS icon grid: 824/1024 with a ~22% corner radius.
    let size = CGFloat(pixels)
    let body = NSRect(x: size * 0.098, y: size * 0.098, width: size * 0.804, height: size * 0.804)
    let shape = NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225)
    NSGradient(colors: [
        NSColor(srgbRed: 0.08, green: 0.09, blue: 0.16, alpha: 1),
        NSColor(srgbRed: 0.20, green: 0.17, blue: 0.30, alpha: 1),
    ])!.draw(in: shape, angle: 90)

    // A warm glow behind the sun.
    NSGraphicsContext.current?.saveGraphicsState()
    shape.addClip()
    NSGradient(colors: [
        NSColor(srgbRed: 1.0, green: 0.72, blue: 0.25, alpha: 0.75),
        NSColor(srgbRed: 1.0, green: 0.55, blue: 0.15, alpha: 0),
    ])!.draw(fromCenter: NSPoint(x: body.midX, y: body.midY), radius: 0,
             toCenter: NSPoint(x: body.midX, y: body.midY), radius: body.width * 0.55, options: [])
    NSGraphicsContext.current?.restoreGraphicsState()

    let config = NSImage.SymbolConfiguration(pointSize: body.width * 0.5, weight: .bold)
        .applying(.init(paletteColors: [NSColor(srgbRed: 1.0, green: 0.97, blue: 0.85, alpha: 1)]))
    if let sun = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        sun.draw(in: NSRect(x: body.midX - sun.size.width / 2, y: body.midY - sun.size.height / 2,
                            width: sun.size.width, height: sun.size.height))
    }

    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(output)/icon_\(name).png"))
}
