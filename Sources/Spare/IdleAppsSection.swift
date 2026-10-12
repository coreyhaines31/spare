import SwiftUI
import SpareCore

/// Apps left open but unused for a while, with a reviewed quit for each or for all of them.
struct IdleAppsSection: View {
    @ObservedObject var monitor: Monitor
    @State private var expanded = false
    @State private var confirming: Set<String>?

    var body: some View {
        let apps = monitor.idleApps
        let total = apps.reduce(UInt64(0)) { $0 + $1.workload.memory }
        VStack(alignment: .leading, spacing: 8) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "moon.zzz").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Not used lately").font(.body.weight(.medium))
                        Text("\(apps.count) app\(apps.count == 1 ? "" : "s") idle 2+ hours · \(DisplayFormat.memory(total))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption).foregroundStyle(.secondary)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            if expanded {
                if let confirming {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Spare will ask \(confirming.count == 1 ? "this app" : "these \(confirming.count) apps") to quit normally. Apps with unsaved work will ask you to save first.")
                            .font(.caption).fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button("Cancel") { self.confirming = nil }.keyboardShortcut(.cancelAction)
                            Spacer()
                            Button("Quit", role: .destructive) {
                                for app in apps where confirming.contains(app.workload.id) { monitor.stop(app.workload) }
                                self.confirming = nil
                            }.buttonStyle(.borderedProminent).tint(.red).controlSize(.small)
                        }
                    }.padding(10).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                }
                ForEach(apps, id: \.workload.id) { app in
                    HStack(spacing: 10) {
                        WorkloadIcon(workload: app.workload).frame(width: 22, height: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.workload.name).font(.callout).lineLimit(1)
                            Text(IdleApps.describe(app.idle).capitalizedFirst).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(DisplayFormat.memory(app.workload.memory)).font(.callout).monospacedDigit()
                        Button("Quit…") { confirming = [app.workload.id] }.controlSize(.small)
                    }
                }
                if apps.count > 1 {
                    Button("Quit all \(apps.count)…") { confirming = Set(apps.map(\.workload.id)) }.controlSize(.small)
                }
            }
        }.padding(.horizontal, 16).padding(.bottom, 12)
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
