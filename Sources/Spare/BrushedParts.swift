import PanelKit
import SwiftUI

// Small pieces of the Brushed popover that PanelKit doesn't have yet, drawn with PanelKit's tokens.

/// A 22-point metal key with a symbol, for the toolbar buttons that sit in the fascia.
struct FasciaKey: View {
    let symbol: String
    @Environment(\.panelTheme) private var theme
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(theme.ink)
            .frame(width: 24, height: 22)
            .background(RoundedRectangle(cornerRadius: 4).fill(LinearGradient(colors: theme.button2, startPoint: .top, endPoint: .bottom)))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(theme.button2Edge, lineWidth: 1))
            .shadow(color: .black.opacity(0.12), radius: 0, y: 1)
            .contentShape(Rectangle())
    }
}

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
