import AppKit

// Renders Spare's app icon from the shared gauge glyph. Built with Sources/Spare/GaugeGlyph.swift.
let directory = CommandLine.arguments[1]
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = Double(size * scale)
        let image = NSImage(size: NSSize(width: pixels, height: pixels), flipped: true) { bounds in
            // macOS icon grid: an 824-point rounded square centered on a 1024-point canvas.
            let tile = bounds.insetBy(dx: pixels * 100 / 1024, dy: pixels * 100 / 1024)
            let shape = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.2237, yRadius: tile.width * 0.2237)
            NSGradient(starting: NSColor(srgbRed: 0.263, green: 0.275, blue: 0.302, alpha: 1),
                       ending: NSColor(srgbRed: 0.098, green: 0.106, blue: 0.125, alpha: 1))?.draw(in: shape, angle: 90)
            NSColor(srgbRed: 0.388, green: 0.4, blue: 0.431, alpha: 1).setStroke()
            shape.lineWidth = max(1, pixels / 512)
            shape.stroke()
            let glyph = tile.insetBy(dx: tile.width * 0.16, dy: tile.width * 0.16)
            GaugeGlyph(dial: NSColor(srgbRed: 0.961, green: 0.961, blue: 0.969, alpha: 1),
                       ticks: NSColor(srgbRed: 0.718, green: 0.737, blue: 0.776, alpha: 1),
                       needle: NSColor(srgbRed: 1, green: 0.624, blue: 0.039, alpha: 1)).draw(in: glyph)
            return true
        }
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(pixels), pixelsHigh: Int(pixels),
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        if let data = bitmap.representation(using: .png, properties: [:]) {
            try data.write(to: URL(fileURLWithPath: directory + "/icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"))
        }
    }
}
