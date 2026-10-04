import SwiftUI
import SpareCore

struct MemoryTrendView: View {
    let trend: MemoryTrend
    private var peak: UInt64 { max(1, trend.points.map(\.bytes).max() ?? 1) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(trend.summary).font(.system(size: 13, weight: .medium))
            Sparkline(values: trend.points.map { Double($0.bytes) / Double(peak) * 100 })
                .frame(height: 55).foregroundStyle(Color.accentColor)
                .accessibilityLabel("Memory history. \(trend.summary). Peak \(DisplayFormat.memory(peak)).")
            HStack {
                Text("Scale: 0–\(DisplayFormat.memory(peak))")
                Spacer()
                Text("Up to 5 minutes")
            }.font(.system(size: 10)).foregroundStyle(.secondary)
            Text(trend.membershipChanged ? "The processes in this group changed during this period. Growth includes any added helpers or sessions." :
                "Growth can be normal while an app loads content or a task does more work. This is not a memory-leak diagnosis.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
