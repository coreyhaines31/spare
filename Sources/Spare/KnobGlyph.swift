import AppKit
import SpareCore

/// Spare's menu bar knob, drawn from the same geometry as mac-app-kit's `glyphs/spare` assets (Scripts/glyphs/glyphs.mjs):
/// an 18-point dial open at the bottom with a heavy red-zone end, and a solid knob whose pointer is cut out of it.
/// The pointer turns with load: about 0.2 calm, 0.6 busy, 0.92 under memory pressure. Draw into a flipped context.
enum KnobGlyph {
    /// Where the pointer sits (0...1) for the latest reading. Memory pressure holds it in the busy or red zone even when
    /// the CPU is quiet, because pressure is what slows a Mac down.
    static func value(cpu: Double?, pressure: MemoryPressure?, ready: Bool) -> Double {
        guard ready, let cpu else { return 0.2 }
        var value = min(max(cpu / 100, 0), 1)
        if pressure == .warning { value = max(value, 0.6) }
        if pressure == .critical { value = max(value, 0.92) }
        // Steps of 2% keep the image stable between nearly identical readings.
        return (value * 50).rounded() / 50
    }

    static func draw(value: Double, in rect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: rect.minX, yBy: rect.minY)
        transform.scale(by: rect.width / 18)
        transform.concat()
        NSColor.black.setStroke()
        NSColor.black.setFill()

        stroke(arc(from: -135, to: 95), width: 1)
        stroke(arc(from: 95, to: 135), width: 2.2)
        NSBezierPath(ovalIn: NSRect(x: 9 - 5.3, y: 9 - 5.3, width: 10.6, height: 10.6)).fill()

        let angle = -135 + min(max(value, 0), 1) * 270
        let pointer = NSBezierPath()
        pointer.move(to: point(radius: 1.4, degrees: angle))
        pointer.line(to: point(radius: 4.2, degrees: angle))
        NSGraphicsContext.current?.compositingOperation = .destinationOut
        stroke(pointer, width: 1.5)
        NSGraphicsContext.restoreGraphicsState()
    }

    /// A template image sized for the menu bar, tinted by the system like an SF Symbol.
    static func image(value: Double) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { rect in
            draw(value: value, in: rect)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Spare"
        return image
    }

    /// A point on a circle around the knob's centre; 0 degrees is straight up, positive turns clockwise.
    private static func point(radius: CGFloat, degrees: Double) -> NSPoint {
        let radians = (degrees - 90) * .pi / 180
        return NSPoint(x: 9 + radius * cos(radians), y: 9 + radius * sin(radians))
    }

    private static func arc(from start: Double, to end: Double) -> NSBezierPath {
        let path = NSBezierPath()
        let steps = max(2, Int((end - start) / 3))
        for step in 0...steps {
            let location = point(radius: 7.9, degrees: start + (end - start) * Double(step) / Double(steps))
            if step == 0 { path.move(to: location) } else { path.line(to: location) }
        }
        return path
    }

    private static func stroke(_ path: NSBezierPath, width: CGFloat) {
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }
}
