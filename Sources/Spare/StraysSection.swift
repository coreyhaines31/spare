import SwiftUI
import SpareCore

/// Processes agents and tools left running, with a reviewed stop for each or for all of them.
struct StraysSection: View {
    @ObservedObject var monitor: Monitor
    @State private var expanded = false
    @State private var confirming: Set<ProcessIdentity>?

    var body: some View {
        let strays = monitor.strays
        let total = strays.reduce(UInt64(0)) { $0 + $1.memory }
        VStack(alignment: .leading, spacing: 8) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "pawprint").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Left running by agents").font(.body.weight(.medium))
                        Text("\(strays.count) stray\(strays.count == 1 ? "" : "s") nothing owns · \(DisplayFormat.memory(total))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption).foregroundStyle(.secondary)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            if expanded {
                if let confirming {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Spare will stop \(confirming.count == 1 ? "this" : "these \(confirming.count)") and everything \(confirming.count == 1 ? "it" : "they") started. Anything still running a few seconds later is force-stopped.")
                            .font(.caption).fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button("Cancel") { self.confirming = nil }.keyboardShortcut(.cancelAction)
                            Spacer()
                            Button("Stop", role: .destructive) {
                                monitor.stopStrays(strays.filter { confirming.contains($0.root.identity) })
                                self.confirming = nil
                            }.buttonStyle(.borderedProminent).tint(.red).controlSize(.small)
                        }
                    }.padding(10).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                }
                ForEach(strays, id: \.root.identity) { stray in
                    HStack(spacing: 10) {
                        Image(systemName: stray.kind.symbol).foregroundStyle(.secondary).frame(width: 22, height: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(stray.name) · \(stray.kind.label)").font(.callout).lineLimit(1)
                            Text(stray.reason).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Text(DisplayFormat.memory(stray.memory)).font(.callout).monospacedDigit()
                        Button("Stop…") { confirming = [stray.root.identity] }.controlSize(.small)
                    }.help("PID \(stray.root.identity.pid) · \(stray.tree.count) process\(stray.tree.count == 1 ? "" : "es")")
                }
                if strays.count > 1 {
                    Button("Stop all \(strays.count)…") { confirming = Set(strays.map(\.root.identity)) }.controlSize(.small)
                }
            }
        }.padding(.horizontal, 16).padding(.bottom, 12)
    }
}
