import SwiftUI
import SpareCore
import PanelKit

struct MemoryTrendView: View {
    let trend: MemoryTrend
    @Environment(\.brushed) private var theme
    private var peak: UInt64 { max(1, trend.points.map(\.bytes).max() ?? 1) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(trend.summary).font(PanelFont.body(12.5, .medium))
            Sparkline(values: trend.points.map { Double($0.bytes) / Double(peak) * 100 })
                .frame(height: 55).foregroundStyle(theme.ink)
                .padding(6).background(RoundedRectangle(cornerRadius: 6).fill(theme.field))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.line, lineWidth: 1))
                .accessibilityLabel("Memory history. \(trend.summary). Peak \(DisplayFormat.memory(peak)).")
            HStack {
                Text("Scale: 0–\(DisplayFormat.memory(peak))")
                Spacer()
                Text("Up to 5 minutes")
            }.font(PanelFont.body(10)).foregroundStyle(theme.sub).monospacedDigit()
            Text(trend.membershipChanged ? "The processes in this group changed during this period. Growth includes any added helpers or sessions." :
                "Growth can be normal while an app loads content or a task does more work. This is not a memory-leak diagnosis.")
                .font(PanelFont.body(11)).foregroundStyle(theme.sub).fixedSize(horizontal: false, vertical: true)
        }
    }
}
