import SwiftUI
import SpareCore
import PanelKit

/// Processes agents and tools left running, with a reviewed stop for each or for all of them.
struct StraysSection: View {
    @ObservedObject var monitor: Monitor
    @State private var expanded = false
    @State private var confirming: Set<ProcessIdentity>?
    @Environment(\.panelTheme) private var theme

    var body: some View {
        let strays = monitor.strays
        let total = strays.reduce(UInt64(0)) { $0 + $1.memory }
        Disclosure("Left running by agents",
                   subtitle: "\(strays.count) stray\(strays.count == 1 ? "" : "s") nothing owns · \(DisplayFormat.memory(total))",
                   isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 0) {
                if let confirming {
                    ConfirmBox(message: "Spare will stop \(confirming.count == 1 ? "this" : "these \(confirming.count)") and everything \(confirming.count == 1 ? "it" : "they") started. Anything still running a few seconds later is force-stopped.",
                               actionTitle: "Stop", cancel: { self.confirming = nil }, confirm: {
                        monitor.stopStrays(strays.filter { confirming.contains($0.root.identity) })
                        self.confirming = nil
                    }).padding(.horizontal, 14).padding(.vertical, 4)
                }
                ForEach(strays, id: \.root.identity) { stray in
                    WrapRow(name: "\(stray.name) · \(stray.kind.label)", subtitle: stray.reason, icon: SymbolTile(symbol: stray.kind.symbol)) {
                        Text(DisplayFormat.memory(stray.memory)).font(PanelFont.body(13)).monospacedDigit().fixedSize()
                        Button("Stop…") { confirming = [stray.root.identity] }.buttonStyle(.panelCompact).fixedSize()
                    }.help("PID \(stray.root.identity.pid) · \(stray.tree.count) process\(stray.tree.count == 1 ? "" : "es")")
                }
                if strays.count > 1 {
                    Button("Stop all \(strays.count)…") { confirming = Set(strays.map(\.root.identity)) }
                        .buttonStyle(.panelCompact).padding(.horizontal, 14).padding(.vertical, 6)
                }
            }.padding(.bottom, 6)
        }.overlay(alignment: .top) { Rectangle().fill(theme.line).frame(height: 1) }
    }
}
