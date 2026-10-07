import SwiftUI
import SpareCore
import ServiceManagement

struct Dashboard: View {
    @ObservedObject var monitor: Monitor
    @State private var path: [Workload] = []
    @State private var showingActivity = false
    @State private var showingHelp = false
    @State private var query = ""
    @State private var sortCPU = false
    @State private var includeBackground = false
    @State private var filter = WorkloadFilter.all
    private var visible: [Workload] {
        monitor.workloads.filter {
            (includeBackground || $0.kind != .background) && filter.includes($0) && $0.matches(query)
        }.sorted {
            let left = sortCPU ? $0.cpu : Double($0.memory)
            let right = sortCPU ? $1.cpu : Double($1.memory)
            return left == right ? $0.id < $1.id : left > right
        }
    }
    private var growing: Workload? {
        monitor.workloads.filter { monitor.memoryTrends[$0.id]?.isGrowing == true }.max {
            (monitor.memoryTrends[$0.id]?.change ?? 0) < (monitor.memoryTrends[$1.id]?.change ?? 0)
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if let selection = path.last {
                WorkloadDetail(selection: selection, monitor: monitor, back: goBack, select: { path.append($0) }).id(selection.id)
            } else if showingActivity {
                ActivityView(monitor: monitor, select: { path.append($0) })
            } else {
                overview
            }
            if let notice = monitor.notice {
                Divider()
                HStack(alignment: .top) {
                    Text(notice).font(.callout).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button { monitor.notice = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless).help("Dismiss message").accessibilityLabel("Dismiss message")
                }.padding(12)
            }
            Divider()
            HStack(spacing: 6) {
                Circle().fill(monitor.error == nil ? Color.green : Color.orange).frame(width: 5, height: 5)
                Text(monitor.error == nil ? "Live · On this Mac only" : "Reconnecting…").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("About these readings") { showingHelp = true }.buttonStyle(.link).font(.caption)
                    .popover(isPresented: $showingHelp) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("About these readings").font(.headline)
                            Text("Updated every 3 seconds. App totals include their helpers. CPU is a share of your entire Mac. Memory estimates may overlap and won’t add up to the system total.")
                            Text("Memory pressure describes how hard macOS is working to make room. Lots of used memory can be normal.")
                        }.font(.callout).padding(16).frame(width: 300)
                    }
            }.padding(.horizontal, 14).padding(.vertical, 10)
        }.font(.body).frame(width: SpareLayout.width, height: SpareLayout.height)
            .background(Color(nsColor: .windowBackgroundColor))
    }
    private var toolbar: some View {
        HStack(spacing: 10) {
            if !path.isEmpty || showingActivity {
                Button(action: goBack) { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless).help("Back").accessibilityLabel("Back").keyboardShortcut("[", modifiers: .command)
            } else {
                Image(systemName: "leaf").foregroundStyle(.secondary)
            }
            Text(path.isEmpty ? (showingActivity ? "Recent Activity" : "Spare") : "Details").font(.headline)
            Spacer()
            Button { monitor.onOpenRecap?() } label: { Image(systemName: "chart.bar.xaxis") }
                .buttonStyle(.borderless).help("Daily and weekly recap").accessibilityLabel("Daily and weekly recap")
            Button {
                path.removeAll()
                showingActivity.toggle()
            } label: { Image(systemName: "clock.arrow.circlepath") }
                .buttonStyle(.borderless).help("Recent activity").accessibilityLabel("Recent activity")
            Menu {
                Button("Open in a window") { monitor.onOpenWindow?() }
                Toggle("Launch at login", isOn: Binding(get: { monitor.launchesAtLogin }, set: monitor.setLaunchAtLogin))
                if monitor.loginStatus == .requiresApproval {
                    Button("Approve in Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                }
                Toggle("Warn about sustained pressure", isOn: Binding(get: { monitor.alerts }, set: monitor.setAlerts))
                Toggle("Show unidentified processes", isOn: Binding(get: { includeBackground }, set: {
                    includeBackground = $0
                    if $0 { filter = .all }
                }))
                Divider()
                Button("Check for Updates…") { monitor.onCheckForUpdates?() }
                Button("Open Activity Monitor") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")) }
                Button("Quit Spare") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
            } label: { Image(systemName: "gearshape") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 20)
                .help("Settings").accessibilityLabel("Settings")
        }.padding(.horizontal, 16).padding(.vertical, 12)
    }
    private var overview: some View {
        VStack(spacing: 0) {
            ResourceSummary(monitor: monitor)
            if let recap = monitor.awayRecap {
                AwayRecapView(recap: recap, monitor: monitor).padding(.horizontal, 16).padding(.bottom, 12)
            }
            if let suggestion = ReviewSuggestion.make(workloads: monitor.workloads, samples: monitor.samples, ready: monitor.ready) {
                suggestionRow(suggestion.workload, subtitle: suggestionSubtitle(suggestion.workload), symbol: "exclamationmark.circle")
            } else if let growing, let trend = monitor.memoryTrends[growing.id] {
                suggestionRow(growing, subtitle: trend.summary, symbol: "chart.line.uptrend.xyaxis")
            }
            Divider()
            VStack(spacing: 10) {
                NativeSearchField(text: $query).frame(height: 24)
                Picker("Show", selection: $filter) {
                    ForEach(WorkloadFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).labelsHidden()
                HStack {
                    Text("Using the most").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    Spacer()
                    Picker("Sort by", selection: $sortCPU) { Text("Memory").tag(false); Text("CPU").tag(true) }
                        .pickerStyle(.menu).labelsHidden().frame(width: 105).controlSize(.small)
                }
            }.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 4)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(visible) { workload in
                        WorkloadRow(workload: workload, sortCPU: sortCPU) { path.append(workload) }
                    }
                    if visible.isEmpty {
                        VStack(spacing: 8) {
                            Text(monitor.ready ? "No matching items" : "Finding your apps…").font(.headline)
                            if monitor.ready { Text("Try a different search or category.").foregroundStyle(.secondary) }
                        }.frame(maxWidth: .infinity).padding(.vertical, 32)
                    }
                }.padding(.horizontal, 8).padding(.bottom, 8)
            }
        }
    }
    private func suggestionRow(_ workload: Workload, subtitle: String, symbol: String) -> some View {
        Button { path.append(workload) } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(workload.name).font(.body.weight(.medium)).lineLimit(1)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }.contentShape(Rectangle()).padding(.horizontal, 16).padding(.bottom, 12)
        }.buttonStyle(.plain).help("Review current readings for \(workload.name)")
    }
    private func suggestionSubtitle(_ workload: Workload) -> String {
        let pressure = monitor.samples.last?.pressure
        let resource = pressure == .warning || pressure == .critical ? "\(DisplayFormat.memory(workload.memory)) memory" : "\(DisplayFormat.percent(workload.cpu)) CPU"
        return "\(resource) · Review before closing"
    }
    private func goBack() {
        if !path.isEmpty { path.removeLast() } else { showingActivity = false }
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
            else { Image(systemName: workload.kind.symbol).resizable().scaledToFit().padding(7).foregroundStyle(.secondary) }
        }.frame(width: 32, height: 32)
    }
}
