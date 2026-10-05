import SwiftUI
import UniformTypeIdentifiers
import SpareCore

struct RecapView: View {
    @ObservedObject var monitor: Monitor
    @State private var period = RecapPeriod.today
    @State private var sortCPU = true
    @State private var confirmingClear = false
    @State private var exportError: String?
    private var report: RecapReport? { monitor.recaps[period] }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 20) {
                Picker("Recap period", selection: $period) {
                    ForEach(RecapPeriod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 420)
                Spacer(minLength: 0)
                Button("Export CSV…", systemImage: "square.and.arrow.up") { export() }
                    .disabled(report?.totals.observed ?? 0 <= 0)
            }.padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let error = monitor.recapError { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                    if !monitor.savingHistory { Label("Recording paused", systemImage: "pause.circle").foregroundStyle(.secondary) }
                    if let recap = monitor.awayRecap { AwayRecapView(recap: recap, monitor: monitor) }
                    if let report {
                        Text(report.summary).font(.title3).fixedSize(horizontal: false, vertical: true)
                        coverage(report)
                        if report.totals.observed > 0 {
                            metrics(report)
                            RecapChart(report: report, period: period)
                            comparison(report)
                            Divider()
                            ranking(report)
                            busyPeriods(report)
                        }
                    } else { ProgressView("Loading local history…") }
                    Divider()
                    historyControls
                }.padding(24).frame(maxWidth: 1000).frame(maxWidth: .infinity)
            }
        }.background(Color(nsColor: .windowBackgroundColor))
            .onAppear { monitor.refreshRecaps() }
            .alert("Clear all saved recap history?", isPresented: $confirmingClear) {
                Button("Cancel", role: .cancel) {}
                Button("Clear history", role: .destructive) { monitor.clearRecaps() }
            } message: { Text("This removes all 30 days of saved summaries from this Mac. If recording is enabled, new history will start with the next readings.") }
            .alert("Couldn’t export recap", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
                Button("OK") { exportError = nil }
            } message: { Text(exportError ?? "") }
    }
    private func coverage(_ report: RecapReport) -> some View {
        HStack {
            Text("\(RecapFormat.duration(report.totals.observed)) recorded · \(RecapFormat.duration(report.unobserved)) unobserved")
            ContextHelp(title: "Recorded time", text: "Coverage since \(report.interval.start.formatted(.dateTime.month(.abbreviated).day().hour().minute())). Sleep, closed-app time, recording pauses, and missed samples are unobserved. History starts when Spare runs; earlier activity cannot be recovered. Memory pressure was unavailable for \(RecapFormat.duration(report.totals.observed - report.totals.knownPressureSeconds)) of recorded time.")
        }.font(.callout).foregroundStyle(.secondary)
    }
    private func metrics(_ report: RecapReport) -> some View {
        HStack(alignment: .top, spacing: 20) {
            metric("Average CPU", DisplayFormat.percent(report.totals.averageCPU), help: "A time-weighted share of your entire Mac’s processing capacity during recorded time.")
            metric("CPU above 85%", RecapFormat.duration(report.totals.busySeconds), help: "Observed time with more than 85% of total CPU capacity in use. Busy work can be intentional; this does not diagnose a slowdown.")
            metric("Memory pressure", report.totals.knownPressureSeconds > 0 ? RecapFormat.duration(report.totals.pressureSeconds) : "Unavailable", help: "Time macOS reported warning or critical memory pressure. High memory use alone is not a problem. Unavailable readings are excluded.")
        }
    }
    private func metric(_ title: String, _ value: String, help: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) { Text(title); ContextHelp(title: title, text: help) }.font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.semibold)).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    @ViewBuilder private func comparison(_ report: RecapReport) -> some View {
        if report.totals.observed >= 60, report.previous.observed >= 60 {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Compared with \(period.comparisonLabel)").font(.subheadline.weight(.medium))
                    ContextHelp(title: "Period comparison", text: "Based on \(RecapFormat.duration(report.totals.observed)) recorded in this period and \(RecapFormat.duration(report.previous.observed)) in the previous period. Coverage may differ. CPU and memory-pressure comparisons use averages and proportions, not total elapsed time.")
                }
                let delta = report.totals.averageCPU - report.previous.averageCPU
                Text("Average CPU \(delta >= 0 ? "+" : "")\(String(format: "%.1f", delta)) percentage points")
                if let current = report.totals.pressurePercent, let previous = report.previous.pressurePercent {
                    Text("Elevated memory pressure: \(DisplayFormat.percent(current)) of known readings, previously \(DisplayFormat.percent(previous)).")
                }
            }.font(.callout)
        } else {
            HStack {
                Text("Building your comparison with \(period.comparisonLabel)").font(.callout).foregroundStyle(.secondary)
                ContextHelp(title: "Period comparison", text: "Comparisons appear after at least one minute is recorded in both periods. No past activity is inferred or backfilled.")
            }
        }
    }
    private func ranking(_ report: RecapReport) -> some View {
        let ranked = report.workloads.sorted {
            let left = sortCPU ? $0.cpuSeconds : $0.memoryByteSeconds
            let right = sortCPU ? $1.cpuSeconds : $1.memoryByteSeconds
            return left == right ? $0.id < $1.id : left > right
        }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Biggest resource users").font(.headline)
                ContextHelp(title: "Resource rankings", text: "Time-weighted averages across all recorded time, including when a task wasn’t running. Seen time is not active use. Includes identified apps, projects, and agents, without counting their nested sessions twice. Up to 128 groups per hour; smaller tasks may be omitted. Memory estimates can overlap.")
                Spacer()
                Picker("Rank by", selection: $sortCPU) { Text("CPU").tag(true); Text("Memory").tag(false) }
                    .labelsHidden().frame(width: 120).controlSize(.small)
            }
            ForEach(Array(ranked.prefix(8))) { item in
                HStack(spacing: 12) {
                    Image(systemName: item.kind.symbol).foregroundStyle(.secondary).frame(width: 22)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.name).font(.body.weight(.medium)).lineLimit(2)
                        Text("\(item.kind.label) · Seen for \(RecapFormat.duration(item.observed))").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Text(sortCPU ? RecapFormat.cpu(item.cpuSeconds / report.totals.observed) : DisplayFormat.memory(UInt64(item.memoryByteSeconds / report.totals.observed)))
                        .monospacedDigit().font(.body)
                }.padding(.vertical, 3)
            }
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
                        Text(bucket.start, format: .dateTime.month(.abbreviated).day().hour().minute()).fontWeight(.medium)
                        Text("\(RecapFormat.duration(bucket.totals.pressureSeconds)) memory pressure · \(RecapFormat.duration(bucket.totals.busySeconds)) CPU above 85%")
                        let leaders = bucket.workloads.values.sorted {
                            bucket.totals.pressureSeconds > 0 ? $0.pressureByteSeconds > $1.pressureByteSeconds : $0.cpuSeconds > $1.cpuSeconds
                        }.prefix(3).map(\.name)
                        Text("Largest recorded users: \(leaders.isEmpty ? "none identified" : leaders.joined(separator: ", ")).").foregroundStyle(.secondary)
                    }
                }
                Text("Resource use does not establish the cause of a slowdown. CPU and memory pressure time can overlap.").foregroundStyle(.secondary)
            }.font(.callout).padding(.top, 12).frame(maxWidth: .infinity, alignment: .leading)
        }.font(.subheadline)
    }
    private var historyControls: some View {
        HStack {
            Toggle("Save history on this Mac", isOn: Binding(get: { monitor.savingHistory }, set: monitor.setSavingHistory))
            ContextHelp(title: "Local history", text: "Keeps up to 30 days of hourly summaries, including app and project names. No cloud upload. Recaps refresh every 30 seconds and save every minute and on normal quit or sleep. An unexpected quit may lose the last minute. Pausing also clears the temporary away summary; existing saved recaps remain available.")
            Spacer()
            Button("Clear history…", role: .destructive) { confirmingClear = true }
        }.controlSize(.small)
    }
    private func export() {
        guard let report, report.totals.observed > 0 else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Spare \(period.rawValue).csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do { try RecapCSV.make(report).write(to: url, atomically: true, encoding: .utf8) }
            catch { exportError = error.localizedDescription }
        }
    }
}
