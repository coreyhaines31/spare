import AppKit

let directory = CommandLine.arguments[1]
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let bounds = NSRect(x: 0, y: 0, width: pixels, height: pixels)
        NSColor(calibratedRed: 0.09, green: 0.29, blue: 0.22, alpha: 1).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: Double(pixels) * 0.04, dy: Double(pixels) * 0.04),
                     xRadius: Double(pixels) * 0.22, yRadius: Double(pixels) * 0.22).fill()
        let symbol = NSImage(systemSymbolName: "leaf.fill", accessibilityDescription: nil)
        let configuration = NSImage.SymbolConfiguration(pointSize: Double(pixels) * 0.54, weight: .regular)
            .applying(.init(paletteColors: [NSColor(calibratedRed: 0.77, green: 0.93, blue: 0.69, alpha: 1)]))
        symbol?.withSymbolConfiguration(configuration)?.draw(in: bounds.insetBy(dx: Double(pixels) * 0.23, dy: Double(pixels) * 0.23))
        image.unlockFocus()
        if let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
           let data = bitmap.representation(using: .png, properties: [:]) {
            try data.write(to: URL(fileURLWithPath: directory + "/icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"))
        }
    }
}
