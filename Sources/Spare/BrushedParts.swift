import PanelKit
import SwiftUI

// Small pieces of the Brushed popover that PanelKit doesn't have yet, drawn with PanelKit's tokens.

extension EnvironmentValues {
    /// PanelKit's colours for the current appearance.
    var brushed: PanelTheme { panelThemeOverride ?? PanelTheme.resolve(colorScheme) }
}

/// A 22-point metal key with a symbol, for the toolbar buttons that sit in the fascia.
struct FasciaKey: View {
    let symbol: String
    @Environment(\.brushed) private var theme
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

/// Popover buttons: a compact metal key, or a red key for the action that stops or quits something.
struct SpareButtonStyle: ButtonStyle {
    enum Kind { case secondary, destructive }
    var kind = Kind.secondary
    var compact = true

    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration, kind: kind, compact: compact)
    }

    private struct Styled: View {
        let configuration: Configuration
        let kind: Kind
        let compact: Bool
        @Environment(\.brushed) private var theme
        @Environment(\.isEnabled) private var isEnabled
        var body: some View {
            let shape = RoundedRectangle(cornerRadius: compact ? 4 : 5)
            configuration.label
                .font(PanelFont.body(compact ? 11.5 : 12.5, .semibold))
                .lineLimit(1)
                .foregroundStyle(kind == .destructive ? Color.white : theme.ink)
                .padding(.vertical, compact ? 4 : 7)
                .padding(.horizontal, compact ? 9 : 12)
                .background {
                    switch kind {
                    case .secondary:
                        shape.fill(LinearGradient(colors: theme.button2, startPoint: .top, endPoint: .bottom))
                            .overlay(shape.strokeBorder(theme.button2Edge, lineWidth: 1))
                    case .destructive:
                        shape.fill(theme.stop).overlay(shape.strokeBorder(.black.opacity(0.2), lineWidth: 1))
                    }
                }
                .shadow(color: .black.opacity(0.08), radius: 0, y: 1)
                .opacity(configuration.isPressed ? 0.8 : (isEnabled ? 1 : 0.5))
                .contentShape(Rectangle())
        }
    }
}

extension ButtonStyle where Self == SpareButtonStyle {
    static var key: SpareButtonStyle { SpareButtonStyle() }
    static var wideKey: SpareButtonStyle { SpareButtonStyle(compact: false) }
    static var stopKey: SpareButtonStyle { SpareButtonStyle(kind: .destructive) }
}

/// A text link in the panel's secondary ink.
struct PanelLinkStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration)
    }
    private struct Styled: View {
        let configuration: Configuration
        @Environment(\.brushed) private var theme
        var body: some View {
            configuration.label
                .font(PanelFont.body(12, .medium))
                .foregroundStyle(theme.ink2)
                .underline(true, color: theme.ink2.opacity(0.4))
                .opacity(configuration.isPressed ? 0.6 : 1)
                .contentShape(Rectangle())
        }
    }
}

extension ButtonStyle where Self == PanelLinkStyle {
    static var panelLink: PanelLinkStyle { PanelLinkStyle() }
}

/// A recessed box: the reading tiles, confirm boxes and notices.
struct Recess<Content: View>: View {
    var tint: PanelStatus?
    @ViewBuilder let content: Content
    @Environment(\.brushed) private var theme
    var body: some View {
        let color = tint.map { theme.color(for: $0) }
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 6).fill(color.map { $0.opacity(0.12) } ?? theme.field))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(color.map { $0.opacity(0.4) } ?? theme.line, lineWidth: 1))
    }
}

/// A reviewed stop or quit: the consequence, Cancel (Esc) and a red action.
struct ConfirmBox: View {
    var title: String?
    let message: String
    var warning: String?
    let action: String
    var disabled = false
    let cancel: () -> Void
    let confirm: () -> Void
    @Environment(\.brushed) private var theme
    var body: some View {
        Recess {
            VStack(alignment: .leading, spacing: 8) {
                if let title { Text(title).font(PanelFont.body(13, .semibold)) }
                Text(message).font(PanelFont.body(12)).fixedSize(horizontal: false, vertical: true)
                if let warning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill").font(PanelFont.body(12, .medium))
                        .foregroundStyle(theme.caution).fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Button("Cancel", action: cancel).buttonStyle(.key).keyboardShortcut(.cancelAction)
                    Spacer()
                    Button(action, role: .destructive, action: confirm).buttonStyle(.stopKey).disabled(disabled)
                }
            }
        }
    }
}

/// A reading in a recessed tile: caps label, value, and whatever detail follows.
struct ReadingTile<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content
    @Environment(\.brushed) private var theme
    var body: some View {
        Recess {
            VStack(alignment: .leading, spacing: 5) {
                Text(label).font(PanelFont.condensed(10, .semibold)).tracking(2).textCase(.uppercase).foregroundStyle(theme.sub)
                content
            }
        }
    }
}

/// A 22-point metal tile with a symbol, for rows whose item has no app icon.
struct SymbolTile: View {
    let symbol: String
    @Environment(\.brushed) private var theme
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(theme.ink)
            .frame(width: 22, height: 22)
            .background(RoundedRectangle(cornerRadius: 5).fill(LinearGradient(colors: theme.button2, startPoint: .top, endPoint: .bottom)))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(theme.button2Edge, lineWidth: 1))
            .accessibilityHidden(true)
    }
}

/// A heading and a paragraph in the detail view.
struct TextSection: View {
    let heading: String
    let text: String
    @Environment(\.brushed) private var theme
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
    @Environment(\.brushed) private var theme
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

/// A row that opens something and keeps its whole subtitle (up to two lines), unlike PanelKit's one-line `Row`.
struct OpenRow<Icon: View>: View {
    let name: String
    let subtitle: String
    let icon: Icon
    @Environment(\.brushed) private var theme
    var body: some View {
        HStack(spacing: 10) {
            icon.frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(PanelFont.body(13, .semibold)).lineLimit(1)
                Text(subtitle).font(PanelFont.body(11.5)).foregroundStyle(theme.sub).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Text("›").font(PanelFont.body(15)).foregroundStyle(theme.sub).accessibilityHidden(true)
        }
        .padding(.vertical, 7).padding(.horizontal, 14)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
