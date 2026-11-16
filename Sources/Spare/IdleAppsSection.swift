import SwiftUI
import SpareCore
import PanelKit

/// Apps left open but unused for a while, with a reviewed quit for each or for all of them.
struct IdleAppsSection: View {
    @ObservedObject var monitor: Monitor
    @State private var expanded = false
    @State private var confirming: Set<String>?
    @Environment(\.panelTheme) private var theme

    var body: some View {
        let apps = monitor.idleApps
        let total = apps.reduce(UInt64(0)) { $0 + $1.workload.memory }
        Disclosure("Not used lately",
                   subtitle: "\(apps.count) app\(apps.count == 1 ? "" : "s") idle 2+ hours · \(DisplayFormat.memory(total))",
                   isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 0) {
                if let confirming {
                    ConfirmBox(message: "Spare will ask \(confirming.count == 1 ? "this app" : "these \(confirming.count) apps") to quit normally. Apps with unsaved work will ask you to save first.",
                               action: "Quit", cancel: { self.confirming = nil }, confirm: {
                        for app in apps where confirming.contains(app.workload.id) { monitor.stop(app.workload) }
                        self.confirming = nil
                    }).padding(.horizontal, 14).padding(.vertical, 4)
                }
                ForEach(apps, id: \.workload.id) { app in
                    Row(app.workload.name, icon: WorkloadIcon(workload: app.workload, size: 22),
                        subtitle: IdleApps.describe(app.idle).capitalizedFirst) {
                        HStack(spacing: 8) {
                            Text(DisplayFormat.memory(app.workload.memory)).font(PanelFont.body(13)).monospacedDigit()
                            Button("Quit…") { confirming = [app.workload.id] }.buttonStyle(.key)
                        }
                    }
                }
                if apps.count > 1 {
                    Button("Quit all \(apps.count)…") { confirming = Set(apps.map(\.workload.id)) }
                        .buttonStyle(.key).padding(.horizontal, 14).padding(.vertical, 6)
                }
            }.padding(.bottom, 6)
        }.overlay(alignment: .top) { Rectangle().fill(theme.line).frame(height: 1) }
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
