import PanelKit
import SwiftUI

// Small pieces of the Brushed popover that PanelKit doesn't have yet, drawn with PanelKit's tokens.

/// A heading and a paragraph in the detail view.
struct TextSection: View {
    let heading: String
    let text: String
    @Environment(\.panelTheme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(heading)
            Text(text).font(PanelFont.body(12.5)).foregroundStyle(theme.ink2).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14).padding(.bottom, 10)
        }
    }
}

/// Body text in the panel's secondary ink, padded to the row inset.
struct PanelNote: View {
    let text: String
    var color: Color?
    @Environment(\.panelTheme) private var theme
    init(_ text: String, color: Color? = nil) {
        self.text = text
        self.color = color
    }
    var body: some View {
        Text(text).font(PanelFont.body(11.5)).foregroundStyle(color ?? theme.sub)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
    }
}
