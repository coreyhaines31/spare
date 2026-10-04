import SwiftUI
import SpareCore
import ServiceManagement

struct Dashboard: View {
    @ObservedObject var monitor: Monitor
    @State private var selection: Workload?
    @State private var showingActivity = false
    @State private var query = ""
    @State private var sortCPU = false
    @State private var includeBackground = false
    @State private var filter = WorkloadFilter.all
    private var visible: [Workload] {
        monitor.workloads.filter {
            (includeBackground || $0.kind != .background) && filter.includes($0) && $0.matches(query)
        }.sorted { sortCPU ? $0.cpu > $1.cpu : $0.memory > $1.memory }
    }
    private var growing: Workload? {
        monitor.workloads.filter { monitor.memoryTrends[$0.id]?.isGrowing == true }.max {
            (monitor.memoryTrends[$0.id]?.change ?? 0) < (monitor.memoryTrends[$1.id]?.change ?? 0)
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "leaf.fill").foregroundStyle(.green)
                Text("Spare").font(.system(size: 19, weight: .semibold, design: .rounded))
                Spacer()
                Button {
                    selection = nil
                    showingActivity.toggle()
                } label: { Image(systemName: "clock.arrow.circlepath").font(.title3) }
                    .buttonStyle(.plain).help("Recent activity").accessibilityLabel("Recent activity")
                Menu {
                    Button("Open in a window") { monitor.onOpenWindow?() }
                    Toggle("Launch at login", isOn: Binding(get: { monitor.launchesAtLogin }, set: monitor.setLaunchAtLogin))
                    if monitor.loginStatus == .requiresApproval {
                        Button("Approve in Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                    }
                    Toggle("Warn me about sustained pressure", isOn: Binding(get: { monitor.alerts }, set: monitor.setAlerts))
                    Button("Open Activity Monitor") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")) }
                    Divider()
                    Button("Quit Spare") { NSApplication.shared.terminate(nil) }
                } label: { Image(systemName: "ellipsis.circle").font(.title3) }.menuStyle(.borderlessButton).frame(width: 28)
            }.padding(20)
            Divider()
            if let selection {
                WorkloadDetail(selection: selection, monitor: monitor, back: { self.selection = nil }, select: { self.selection = $0 }).id(selection.id)
            } else if showingActivity {
                ActivityView(monitor: monitor, back: { showingActivity = false }, select: {
                    showingActivity = false
                    selection = $0
                })
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        healthCard
                        if let sample = monitor.samples.last {
                            HStack(spacing: 12) {
                                metric("Processing power", value: monitor.ready ? DisplayFormat.percent(sample.cpu) : "…", caption: "of your whole Mac", values: monitor.samples.map(\.cpu))
                                metric("Memory pressure", value: sample.pressure.rawValue.capitalized,
                                    caption: "\(DisplayFormat.memory(sample.memory)) of \(DisplayFormat.memory(sample.physical)) used",
                                    values: monitor.samples.map { $0.physical > 0 ? Double($0.memory) / Double($0.physical) * 100 : 0 })
                            }
                        }
                        if let suggestion = ReviewSuggestion.make(workloads: monitor.workloads, samples: monitor.samples, ready: monitor.ready) {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("A place to start", systemImage: "lightbulb").font(.headline)
                                Text(suggestion.explanation).font(.system(size: 12)).foregroundStyle(.secondary)
                                Button("Review \(suggestion.workload.name)") { selection = suggestion.workload }
                                    .buttonStyle(.bordered)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
                                .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                        }
                        if let growing, let trend = monitor.memoryTrends[growing.id] {
                            GrowingWorkloadView(workload: growing, trend: trend) { selection = growing }
                        }
                        HStack {
                            Text("Using the most").font(.headline)
                            Spacer()
                            Picker("Sort", selection: $sortCPU) { Text("Memory").tag(false); Text("CPU").tag(true) }
                                .pickerStyle(.segmented).frame(width: 145)
                        }
                        Picker("Show", selection: $filter) {
                            ForEach(WorkloadFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }.pickerStyle(.segmented)
                        TextField("Find an app, project, or port", text: $query).textFieldStyle(.roundedBorder)
                        LazyVStack(spacing: 4) {
                            ForEach(visible) { workload in
                                Button { selection = workload } label: {
                                    HStack(spacing: 12) {
                                        WorkloadIcon(workload: workload)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(workload.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                            Text(workload.subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                        Spacer(minLength: 8)
                                        VStack(alignment: .trailing, spacing: 4) {
                                            Text(sortCPU ? DisplayFormat.percent(workload.cpu) : DisplayFormat.memory(workload.memory)).font(.system(size: 13, weight: .medium)).monospacedDigit()
                                            Text(sortCPU ? DisplayFormat.memory(workload.memory) : "\(DisplayFormat.percent(workload.cpu)) CPU").font(.system(size: 10)).foregroundStyle(.secondary)
                                        }
                                        Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(.tertiary)
                                    }.padding(10).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                Divider().padding(.leading, 54)
                            }
                            if visible.isEmpty { Text(monitor.ready ? "No matching apps or projects." : "Finding your apps and projects…").foregroundStyle(.secondary).padding() }
                        }
                        Toggle("Include unidentified background processes", isOn: $includeBackground).font(.caption)
                        Text("App totals include their helpers. CPU is a share of your entire Mac. Memory totals are estimates and won’t add up exactly to system usage.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }.padding(20)
                }
            }
            if let notice = monitor.notice {
                HStack { Text(notice).font(.caption); Spacer(); Button("Dismiss") { monitor.notice = nil } }.padding(12).background(.quaternary)
            }
            Divider()
            HStack {
                Circle().fill(monitor.error == nil ? Color.green : Color.orange).frame(width: 5, height: 5)
                Text(monitor.error ?? "On this Mac only · Updates every 3 seconds").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
            }.padding(12)
        }.frame(width: 470, height: 700).background(Color(nsColor: .windowBackgroundColor))
    }
    private var healthCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Image(systemName: monitor.health.level == 0 ? "leaf" : "exclamationmark.circle")
                Text(monitor.health.level == 0 ? "YOUR MAC, AT A GLANCE" : "WORTH A LOOK").font(.system(size: 10, weight: .semibold)).tracking(1)
            }.foregroundStyle(monitor.health.level == 0 ? Color.green : Color.orange)
            Text(monitor.health.title).font(.system(size: 25, weight: .semibold, design: .rounded))
            Text(monitor.health.message).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
            .background((monitor.health.level == 0 ? Color.green : Color.orange).opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
    }
    private func metric(_ title: String, value: String, caption: String, values: [Double]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 21, weight: .medium, design: .rounded))
            Text(caption).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            Sparkline(values: Array(values.suffix(60))).frame(height: 23).foregroundStyle(.green.opacity(0.7))
        }.frame(maxWidth: .infinity, alignment: .leading).padding(13).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct Sparkline: Shape {
    let values: [Double]
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for (index, value) in values.enumerated() {
            let point = CGPoint(x: Double(index) / Double(max(1, values.count - 1)) * rect.width,
                                y: rect.height * (1 - min(100, max(0, value)) / 100))
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path.strokedPath(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
    }
}

struct WorkloadIcon: View {
    let workload: Workload
    var body: some View {
        Group {
            if let path = workload.appPath { Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable() }
            else { Image(systemName: workload.kind.symbol).resizable().scaledToFit().padding(7).foregroundStyle(.green) }
        }.frame(width: 32, height: 32)
    }
}
