import SwiftUI
import SpareCore

struct RecapView: View {
    @ObservedObject var monitor: Monitor
    @State private var period = RecapPeriod.today
    @State private var sortCPU = true
    @State private var confirmingClear = false
    private var report: RecapReport? { monitor.recaps[period] }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Picker("Recap period", selection: $period) {
                    ForEach(RecapPeriod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                if let error = monitor.recapError { Label(error, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange) }
                if !monitor.savingHistory { Label("Recording paused. Existing history stays available.", systemImage: "pause.circle").font(.callout) }
                if let report {
                    Text(report.summary).font(.callout).fixedSize(horizontal: false, vertical: true)
                    if report.totals.observed > 0 {
                        metrics(report)
                        RecapChart(report: report, period: period)
                        comparison(report)
                        ranking(report)
                        busyPeriods(report)
                    }
                    if report.totals.observed > report.totals.knownPressureSeconds {
                        Text("Memory pressure was unavailable for \(RecapFormat.duration(report.totals.observed - report.totals.knownPressureSeconds)) of recorded time.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Recorded \(RecapFormat.duration(report.totals.observed)) · Unobserved \(RecapFormat.duration(report.unobserved)) since \(report.interval.start.formatted(.dateTime.month(.abbreviated).day().hour().minute())).")
                        .font(.caption).foregroundStyle(.secondary)
                } else { ProgressView("Loading local history…") }
                Divider()
                historyControls
            }.padding(16)
        }.onAppear { monitor.refreshRecaps() }
            .alert("Clear all saved recap history?", isPresented: $confirmingClear) {
                Button("Cancel", role: .cancel) {}
                Button("Clear history", role: .destructive) { monitor.clearRecaps() }
            } message: { Text("This removes all 30 days of saved summaries from this Mac. If recording is enabled, new history will start with the next readings.") }
    }
    private func metrics(_ report: RecapReport) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 14) {
            GridRow {
                metric("Average CPU", DisplayFormat.percent(report.totals.averageCPU))
                metric("CPU above 85%", RecapFormat.duration(report.totals.busySeconds))
            }
            GridRow {
                metric("Elevated memory pressure", report.totals.knownPressureSeconds > 0 ? RecapFormat.duration(report.totals.pressureSeconds) : "Unavailable")
                metric("Recorded time", RecapFormat.duration(report.totals.observed))
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.medium)).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    @ViewBuilder private func comparison(_ report: RecapReport) -> some View {
        if report.totals.observed >= 60, report.previous.observed >= 60 {
            let delta = report.totals.averageCPU - report.previous.averageCPU
            VStack(alignment: .leading, spacing: 5) {
                Text("Compared with \(period == .today ? "yesterday" : "last week")").font(.subheadline.weight(.medium))
                Text("Average CPU: \(delta >= 0 ? "+" : "")\(String(format: "%.1f", delta)) percentage points.")
                if let current = report.totals.pressurePercent, let previous = report.previous.pressurePercent {
                    Text("Memory pressure was elevated in \(DisplayFormat.percent(current)) of known readings, versus \(DisplayFormat.percent(previous)).")
                }
                Text("Based on \(RecapFormat.duration(report.totals.observed)) recorded now and \(RecapFormat.duration(report.previous.observed)) in the previous period. Coverage may differ.").foregroundStyle(.secondary)
            }.font(.caption)
        } else {
            Text("Comparisons appear after at least a minute is recorded in both this period and \(period == .today ? "yesterday" : "last week").")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private func ranking(_ report: RecapReport) -> some View {
        let ranked = report.workloads.sorted {
            let left = sortCPU ? $0.cpuSeconds : $0.memoryByteSeconds
            let right = sortCPU ? $1.cpuSeconds : $1.memoryByteSeconds
            return left == right ? $0.id < $1.id : left > right
        }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Biggest resource users").font(.headline)
                Spacer()
                Picker("Rank by", selection: $sortCPU) { Text("CPU").tag(true); Text("Memory").tag(false) }
                    .labelsHidden().frame(width: 100).controlSize(.small)
            }
            Text("Time-weighted averages across recorded time, including time when a task wasn’t running. Running time is not active use.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(Array(ranked.prefix(8))) { item in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: item.kind.symbol).foregroundStyle(.secondary).frame(width: 20)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.name).font(.body.weight(.medium)).lineLimit(2)
                        Text("\(item.kind.label) · Seen for \(RecapFormat.duration(item.observed))").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Text(sortCPU ? RecapFormat.cpu(item.cpuSeconds / report.totals.observed) : DisplayFormat.memory(UInt64(item.memoryByteSeconds / report.totals.observed)))
                        .monospacedDigit().font(.body)
                }
            }
            Text("Identified apps, projects, and agents only. Up to 128 groups per hour; smaller tasks may be omitted. Memory estimates can overlap.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private func busyPeriods(_ report: RecapReport) -> some View {
        let busy = report.buckets.filter { $0.totals.pressureSeconds > 0 || $0.totals.busySeconds > 0 }.sorted {
            ($0.totals.pressureSeconds + $0.totals.busySeconds) > ($1.totals.pressureSeconds + $1.totals.busySeconds)
        }
        return DisclosureGroup("Busiest recorded hours (\(busy.count))") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(busy.prefix(8))) { bucket in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(bucket.start, format: .dateTime.weekday(.abbreviated).hour().minute()).fontWeight(.medium)
                        Text("\(RecapFormat.duration(bucket.totals.pressureSeconds)) memory pressure · \(RecapFormat.duration(bucket.totals.busySeconds)) CPU above 85%")
                        let leaders = bucket.workloads.values.sorted {
                            bucket.totals.pressureSeconds > 0 ? $0.pressureByteSeconds > $1.pressureByteSeconds : $0.cpuSeconds > $1.cpuSeconds
                        }.prefix(3).map(\.name)
                        Text("Largest recorded users: \(leaders.isEmpty ? "none identified" : leaders.joined(separator: ", ")).").foregroundStyle(.secondary)
                    }
                }
                Text("These readings show what was running, not what caused a slowdown. CPU and memory pressure time can overlap.").foregroundStyle(.secondary)
            }.font(.caption).padding(.top, 8)
        }.font(.subheadline)
    }
    private var historyControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Save recap history on this Mac", isOn: Binding(get: { monitor.savingHistory }, set: monitor.setSavingHistory))
            Text("Keeps 30 days of hourly summaries, including app and project names. No cloud upload. Sleep, closed-app time, and missed readings are unobserved. Updates every 30 seconds; an unexpected quit may lose the last minute.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Clear saved history…", role: .destructive) { confirmingClear = true }.controlSize(.small)
        }
    }
}
