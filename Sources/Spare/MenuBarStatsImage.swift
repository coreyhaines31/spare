import AppKit
import SpareCore

/// The Spare icon followed by a small label-over-number column for each chosen reading.
enum MenuBarStatsImage {
    private static let labelFont = NSFont.systemFont(ofSize: 7.5, weight: .semibold)
    private static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
    private static let height: CGFloat = 22
    private static let glyph: CGFloat = 18
    private static let gap: CGFloat = 4

    static func image(elevated: Bool, stats: [MenuBarStat], readings: MenuBarReadings) -> NSImage {
        guard !stats.isEmpty else { return GaugeGlyph.menuBarImage(elevated: elevated) }
        // Columns are as wide as "100%" so the menu bar doesn't shift as numbers change.
        let column = max(width("100%", valueFont), stats.map { width($0.label, labelFont) }.max() ?? 0)
        let size = NSSize(width: glyph + CGFloat(stats.count) * (gap + column), height: height)
        let image = NSImage(size: size, flipped: true) { _ in
            GaugeGlyph(elevated: elevated).draw(in: NSRect(x: 0, y: (height - glyph) / 2, width: glyph, height: glyph))
            for (index, stat) in stats.enumerated() {
                let x = glyph + gap + CGFloat(index) * (gap + column)
                draw(stat.label, labelFont, centeredIn: NSRect(x: x, y: 1, width: column, height: 9))
                draw(readings.text(stat), valueFont, centeredIn: NSRect(x: x, y: 8.5, width: column, height: 13))
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func width(_ text: String, _ font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    private static func draw(_ text: String, _ font: NSFont, centeredIn rect: NSRect) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        (text as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: NSColor.black, .paragraphStyle: style])
    }
}
