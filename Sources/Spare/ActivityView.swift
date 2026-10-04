import SwiftUI
import SpareCore

struct ActivityView: View {
    @ObservedObject var monitor: Monitor
    let select: (Workload) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Past 15 minutes").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear") { monitor.clearActivity() }.controlSize(.small).disabled(monitor.activity.isEmpty)
                }
                Text("Observed changes, kept on this Mac until you quit Spare. Resource use alone doesn’t explain a slowdown.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                if monitor.activity.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Watching for changes", systemImage: "clock").font(.headline)
                        Text("Pressure changes and recoveries will appear here as Spare monitors your Mac.")
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                    }.padding(18).frame(maxWidth: .infinity, alignment: .leading)

                }
                ForEach(monitor.activity) { event in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: event.level > 0 ? "exclamationmark.circle" : "clock")
                                .foregroundStyle(event.level > 0 ? Color.orange : Color.secondary)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(event.title).font(.headline)
                                Text(event.date, format: .dateTime.hour().minute().second()).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Text(event.message).font(.system(size: 12)).foregroundStyle(.secondary)
                        ForEach(event.items) { item in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(item.name).font(.system(size: 13, weight: .medium)).lineLimit(2)
                                    Spacer()
                                    if let current = monitor.workloads.first(where: { $0.id == item.id }) {
                                        Button("View current") { select(current) }.font(.caption)
                                    }
                                }
                                Text("Then: \(DisplayFormat.memory(item.memory)) · \(DisplayFormat.percent(item.cpu)) CPU")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Divider()
                }
            }.padding(16)
        }
    }
}
