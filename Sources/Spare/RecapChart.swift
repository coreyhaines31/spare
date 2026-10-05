import SwiftUI
import Charts
import SpareCore

struct RecapChart: View {
    let report: RecapReport
    let period: RecapPeriod
    private struct Point: Identifiable {
        var date: Date
        var observed: Double
        var averageCPU: Double
        var pressureSeconds: Double
        var id: Date { date }
    }
    private var points: [Point] {
        let groups = Dictionary(grouping: report.buckets) { period == .today ? $0.start : Calendar.current.startOfDay(for: $0.start) }
        return groups.map { date, buckets in
            let observed = buckets.reduce(0) { $0 + $1.totals.observed }
            return Point(date: date, observed: observed,
                averageCPU: observed > 0 ? buckets.reduce(0) { $0 + $1.totals.cpuSeconds } / observed : 0,
                pressureSeconds: buckets.reduce(0) { $0 + $1.totals.pressureSeconds })
        }.sorted { $0.date < $1.date }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(period == .today ? "CPU by hour" : "CPU by day").font(.headline)
            Chart(points) { point in
                BarMark(x: .value("Time", point.date, unit: period == .today ? .hour : .day), y: .value("Average CPU", point.averageCPU))
                    .foregroundStyle(point.pressureSeconds > 0 ? Color.orange : Color.accentColor)
                    .accessibilityLabel(point.date.formatted(.dateTime.weekday().hour()))
                    .accessibilityValue("\(DisplayFormat.percent(point.averageCPU)) average CPU; \(RecapFormat.duration(point.observed)) recorded; \(RecapFormat.duration(point.pressureSeconds)) elevated memory pressure")
            }.chartYScale(domain: 0...100)
                .chartXScale(domain: report.interval.start...max(report.interval.start.addingTimeInterval(3600), report.interval.end))
                .chartYAxis { AxisMarks(values: [0, 50, 100]) { value in
                    AxisGridLine()
                    AxisValueLabel { if let number = value.as(Int.self) { Text("\(number)%") } }
                } }.frame(height: 120)
            Text("Average CPU during recorded time. Orange marks a period with elevated memory pressure. Missing periods have no bar; partial periods may contain gaps.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
