import SwiftUI
import SpareCore
import PanelKit

struct ActivityView: View {
    @ObservedObject var monitor: Monitor
    let select: (Workload) -> Void
    @Environment(\.panelTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Past 15 minutes").font(PanelFont.condensed(10, .semibold)).tracking(2).textCase(.uppercase)
                        .foregroundStyle(theme.sub)
                    Spacer()
                    Button("Clear") { monitor.clearActivity() }.buttonStyle(.panelCompact).disabled(monitor.activity.isEmpty)
                }.padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 6)
                PanelNote("Observed changes, kept on this Mac until you quit Spare. Resource use alone doesn’t explain a slowdown.")
                    .padding(.bottom, 10)
                if monitor.activity.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Watching for changes", systemImage: "clock").font(PanelFont.body(13, .semibold))
                        Text("Pressure changes and recoveries will appear here as Spare monitors your Mac.")
                            .font(PanelFont.body(12)).foregroundStyle(theme.sub).fixedSize(horizontal: false, vertical: true)
                    }.padding(.horizontal, 14).padding(.vertical, 12)
                        .overlay(alignment: .top) { Rectangle().fill(theme.line).frame(height: 1) }
                }
                ForEach(monitor.activity) { event in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: event.level > 0 ? "exclamationmark.circle" : "clock")
                                .foregroundStyle(event.level > 0 ? theme.caution : theme.sub)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(event.title).font(PanelFont.body(13, .semibold))
                                Text(event.date, format: .dateTime.hour().minute().second()).font(PanelFont.body(11))
                                    .foregroundStyle(theme.sub).monospacedDigit()
                            }
                        }
                        Text(event.message).font(PanelFont.body(12)).foregroundStyle(theme.ink2).fixedSize(horizontal: false, vertical: true)
                        ForEach(event.items) { item in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.name).font(PanelFont.body(12.5, .semibold)).lineLimit(2)
                                    Text("Then: \(DisplayFormat.memory(item.memory)) · \(DisplayFormat.percent(item.cpu)) CPU")
                                        .font(PanelFont.body(11)).foregroundStyle(theme.sub).monospacedDigit()
                                }
                                Spacer()
                                if let current = monitor.workloads.first(where: { $0.id == item.id }) {
                                    Button("View current") { select(current) }.buttonStyle(.panelCompact)
                                }
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .overlay(alignment: .top) { Rectangle().fill(theme.line).frame(height: 1) }
                }
            }
        }
    }
}
