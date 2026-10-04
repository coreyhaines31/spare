import SwiftUI
import SpareCore

struct MemoryTrendView: View {
    let trend: MemoryTrend
    private var peak: UInt64 { max(1, trend.points.map(\.bytes).max() ?? 1) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Memory over time").font(.headline)
            Text(trend.summary).font(.system(size: 13, weight: .medium))
            Sparkline(values: trend.points.map { Double($0.bytes) / Double(peak) * 100 })
                .frame(height: 55).foregroundStyle(.green)
                .accessibilityLabel("Memory history. \(trend.summary). Peak \(DisplayFormat.memory(peak)).")
            HStack {
                Text("Scale: 0–\(DisplayFormat.memory(peak))")
                Spacer()
                Text("Up to 5 minutes")
            }.font(.system(size: 10)).foregroundStyle(.secondary)
            Text(trend.membershipChanged ? "The processes in this group changed during this period. Growth includes any added helpers or sessions." :
                "Growth can be normal while an app loads content or a task does more work. This is not a memory-leak diagnosis.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(14).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct GrowingWorkloadView: View {
    let workload: Workload
    let trend: MemoryTrend
    let review: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Growing recently", systemImage: "chart.line.uptrend.xyaxis").font(.headline)
            Text("\(workload.name) · \(trend.summary)").font(.system(size: 13, weight: .medium))
            Text("More memory doesn’t always mean a problem. Review its recent readings and what it’s doing.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Button("Review \(workload.name)", action: review).buttonStyle(.bordered)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }
}
