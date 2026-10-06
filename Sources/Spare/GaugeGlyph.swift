import AppKit

/// Spare's gauge mark, drawn on the same 32-point grid as the website logo. Draw into a flipped context.
struct GaugeGlyph {
    var dial: NSColor = .black
    var ticks: NSColor = .black
    var needle: NSColor = .black
    /// Points the needle toward the top of the scale, for the elevated-pressure state.
    var elevated = false

    func draw(in rect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: rect.minX, yBy: rect.minY)
        transform.scale(by: rect.width / 32)
        transform.concat()

        let arc = NSBezierPath()
        arc.appendArc(withCenter: NSPoint(x: 16, y: 16.53), radius: 12, startAngle: 135, endAngle: 45, clockwise: false)
        stroke(arc, color: dial, width: 2.5)
        stroke(line(NSPoint(x: 12, y: 27), NSPoint(x: 20, y: 27)), color: dial, width: 2.5)

        let tickPath = NSBezierPath()
        for (start, end) in [((7.0, 16.0), (9.0, 16.0)), ((10.0, 9.0), (11.5, 10.5)), ((16.0, 5.0), (16.0, 8.0)),
                             ((23.0, 9.0), (21.5, 10.5)), ((25.0, 16.0), (23.0, 16.0))] {
            tickPath.append(line(NSPoint(x: start.0, y: start.1), NSPoint(x: end.0, y: end.1)))
        }
        stroke(tickPath, color: ticks, width: 2)

        let tip = elevated ? NSPoint(x: 23.5, y: 16.5) : NSPoint(x: 21, y: 13)
        stroke(line(NSPoint(x: 16, y: 19), tip), color: needle, width: 2.5)
        needle.setFill()
        NSBezierPath(ovalIn: NSRect(x: 13.5, y: 16.5, width: 5, height: 5)).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    /// A template image sized for the menu bar, tinted by the system like an SF Symbol.
    static func menuBarImage(elevated: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { rect in
            GaugeGlyph(elevated: elevated).draw(in: rect)
            return true
        }
        image.isTemplate = true
        return image
    }

    private func line(_ start: NSPoint, _ end: NSPoint) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        return path
    }

    private func stroke(_ path: NSBezierPath, color: NSColor, width: CGFloat) {
        path.lineWidth = width
        path.lineCapStyle = .round
        color.setStroke()
        path.stroke()
    }
}
