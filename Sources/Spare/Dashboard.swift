import SwiftUI
import SpareCore
import PanelKit
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
            (includeBackground || $0.kind != .background || $0.needsAttention) && filter.includes($0) && $0.matches(query)
        }.sorted {
            let left = sortCPU ? $0.cpu : Double($0.memory)
            let right = sortCPU ? $1.cpu : Double($1.memory)
            return left == right ? $0.id < $1.id : left > right
        }
    }
    /// The largest pile of copies of one unidentified program, if any is big enough to look like a runaway.
    private var swarm: Workload? {
        monitor.workloads.filter { $0.needsAttention && $0.processes.count >= Workload.swarmSize }
            .max { $0.processes.count < $1.processes.count }
    }
    private var growing: Workload? {
        monitor.workloads.filter { monitor.memoryTrends[$0.id]?.isGrowing == true }.max {
            (monitor.memoryTrends[$0.id]?.change ?? 0) < (monitor.memoryTrends[$1.id]?.change ?? 0)
        }
    }
    @Environment(\.brushed) private var theme
    var body: some View {
        VStack(spacing: 0) {
            if !path.isEmpty || showingActivity { fascia }
            if let request = monitor.pendingRequest {
                CommandRequestBanner(request: request, monitor: monitor)
            }
            Group {
                if let selection = path.last {
                    WorkloadDetail(selection: selection, monitor: monitor, back: goBack, select: { path.append($0) }).id(selection.id)
                } else if showingActivity {
                    ActivityView(monitor: monitor, select: { path.append($0) })
                } else {
                    overview
                }
            }.frame(maxHeight: .infinity, alignment: .top)
            if let notice = monitor.notice {
                Recess {
                    HStack(alignment: .top) {
                        Text(notice).font(PanelFont.body(12)).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        Button { monitor.notice = nil } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                            .buttonStyle(.plain).foregroundStyle(theme.sub).help("Dismiss message").accessibilityLabel("Dismiss message")
                    }
                }.padding(.horizontal, 14).padding(.vertical, 8)
            }
            footer
        }.font(PanelFont.body(13)).foregroundStyle(theme.ink)
            .frame(width: SpareLayout.width, height: SpareLayout.height)
            .background(theme.background)
            .panelAccent(PanelAccent.spare)
    }
    /// The metal fascia: nameplate and toolbar keys, then the load meter on the overview or a Back key elsewhere.
    /// On the overview it scrolls with the cards, so the list has the full height once you scroll.
    @ViewBuilder private var fascia: some View {
        let detail = !path.isEmpty || showingActivity
        Group {
            if detail {
                Fascia(nameplate: path.isEmpty ? "Recent Activity" : "Details") {
                    Button(action: goBack) { Label("Back", systemImage: "chevron.left") }
                        .buttonStyle(.key).help("Back").keyboardShortcut("[", modifiers: .command)
                }
            } else {
                Fascia(nameplate: "Load", detail: "×10 percent CPU", label: "This Mac") { loadMeter }
            }
        }.overlay(alignment: .topTrailing) { toolbarKeys.padding(.top, 9).padding(.trailing, 14) }
    }
    /// CPU in use on a 0–10 scale (tens of percent), red past 8.
    private var loadMeter: some View {
        let cpu = monitor.ready && monitor.error == nil ? monitor.samples.last?.cpu : nil
        return Meter(MeterConfig(majorTicks: 10, minorTicks: 2, zones: [0.8...1],
                                 labels: [.init(0, "0"), .init(0.2, "2"), .init(0.4, "4"), .init(0.6, "6"), .init(0.8, "8"), .init(1, "10")],
                                 word: "LOAD", accessibilityLabel: "Load meter"),
                     value: (cpu ?? 0) / 100,
                     accessibilityValue: cpu.map { "\(DisplayFormat.percent($0)) CPU" } ?? "Measuring")
    }
    private var toolbarKeys: some View {
        HStack(spacing: 5) {
            Button { monitor.onOpenRecap?() } label: { FasciaKey(symbol: "chart.bar.xaxis") }
                .buttonStyle(.plain).help("Daily and weekly recap").accessibilityLabel("Daily and weekly recap")
            Button {
                path.removeAll()
                showingActivity.toggle()
            } label: { FasciaKey(symbol: "clock.arrow.circlepath") }
                .buttonStyle(.plain).help("Recent activity").accessibilityLabel("Recent activity")
            Menu {
                Button("Open in a window") { monitor.onOpenWindow?() }
                Toggle("Launch at login", isOn: Binding(get: { monitor.launchesAtLogin }, set: monitor.setLaunchAtLogin))
                if monitor.loginStatus == .requiresApproval {
                    Button("Approve in Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                }
                Menu("Show in Menu Bar") {
                    ForEach(MenuBarStat.allCases, id: \.self) { stat in
                        Toggle(stat.title, isOn: Binding(get: { monitor.menuBarStats.contains(stat) },
                                                         set: { monitor.setMenuBarStat(stat, shown: $0) }))
                    }
                    Divider()
                    Toggle("Just the first when only the laptop screen is in use",
                           isOn: Binding(get: { monitor.compactOnLaptopScreen }, set: monitor.setCompactOnLaptopScreen))
                }
                Toggle("Warn about sustained pressure", isOn: Binding(get: { monitor.alerts }, set: monitor.setAlerts))
                Toggle("Show unidentified processes", isOn: Binding(get: { includeBackground }, set: {
                    includeBackground = $0
                    if $0 { filter = .all }
                }))
                Divider()
                Button("Install Command Line Tool…") { monitor.notice = CommandLineInstaller.install() }
                Button("Check for Updates…") { monitor.onCheckForUpdates?() }
                Button("Open Activity Monitor") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")) }
                Button("Quit Spare") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
            } label: { FasciaKey(symbol: "gearshape") }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                .help("Settings").accessibilityLabel("Settings")
        }
    }
    private var footer: some View {
        HStack(spacing: 6) {
            StatusLight(monitor.error == nil ? .go : .caution, monitor.error == nil ? "Live · On this Mac only" : "Reconnecting…")
            Spacer()
            Button("About these readings") { showingHelp = true }.buttonStyle(.plain)
                .font(PanelFont.body(12)).foregroundStyle(theme.sub)
                .popover(isPresented: $showingHelp) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("About these readings").font(.headline)
                        Text("Updated every 3 seconds. App totals include their helpers. CPU is a share of your entire Mac. Memory estimates may overlap and won’t add up to the system total.")
                        Text("Memory pressure describes how hard macOS is working to make room. Lots of used memory can be normal.")
                    }.font(.callout).padding(16).frame(width: 300)
                }
        }.padding(.horizontal, 14).padding(.top, 9).padding(.bottom, 10)
            .overlay(alignment: .top) { Rectangle().fill(theme.line).frame(height: 1) }
    }
    /// Sustained CPU load with healthy memory: the list is most useful sorted by CPU.
    private var cpuIsTheConcern: Bool {
        monitor.health.level > 0 && monitor.samples.last?.pressure == .normal
    }
    /// One scroll for the whole overview, so cards above the list can never squeeze it out of reach. The
    /// search and filters stay pinned while the list scrolls under them.
    private var overview: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                fascia
                overviewCards
                Divider()
                Section {
                    workloadList.padding(.horizontal, 8).padding(.bottom, 8)
                } header: {
                    listControls.background(Color(nsColor: .windowBackgroundColor))
                }
            }
        }.onAppear { if cpuIsTheConcern { sortCPU = true } }
            .onChange(of: cpuIsTheConcern) { if $0 { sortCPU = true } }
    }
    private var overviewCards: some View {
        VStack(spacing: 0) {
            ResourceSummary(monitor: monitor, sortCPU: $sortCPU)
            if let recap = monitor.awayRecap {
                AwayRecapView(recap: recap, monitor: monitor)
            }
            if let swarm {
                suggestionRow(swarm, subtitle: "\(swarm.processes.count) copies running · \(DisplayFormat.percent(swarm.cpu)) CPU · Something may be stuck in a loop",
                              symbol: "exclamationmark.triangle")
            }
            if let suggestion = ReviewSuggestion.make(workloads: monitor.workloads, samples: monitor.samples, ready: monitor.ready) {
                suggestionRow(suggestion.workload, subtitle: suggestionSubtitle(suggestion.workload), symbol: "exclamationmark.circle")
            } else if let growing, let trend = monitor.memoryTrends[growing.id] {
                suggestionRow(growing, subtitle: trend.summary, symbol: "chart.line.uptrend.xyaxis")
            }
            if !monitor.strays.isEmpty { StraysSection(monitor: monitor) }
            if !monitor.idleApps.isEmpty { IdleAppsSection(monitor: monitor) }
        }
    }
    private var listControls: some View {
        VStack(spacing: 10) {
            NativeSearchField(text: $query).frame(height: 24)
            Picker("Show", selection: $filter) {
                ForEach(WorkloadFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).labelsHidden()
            HStack {
                Text("Using the most").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                Picker("Sort by", selection: $sortCPU) { Text("Memory").tag(false); Text("CPU").tag(true) }
                    .pickerStyle(.segmented).labelsHidden().fixedSize().controlSize(.small)
            }
        }.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 6)
    }
    private var workloadList: some View {
        VStack(spacing: 0) {
            ForEach(visible) { workload in
                WorkloadRow(workload: workload, sortCPU: sortCPU,
                            note: monitor.idleApps.first { $0.workload.id == workload.id }.map { IdleApps.describe($0.idle) }
                                ?? workload.activity(in: monitor.agentActivity)?.label,
                            growth: monitor.memoryTrends[workload.id].flatMap { $0.isGrowing ? $0.summary : nil }) {
                    path.append(workload)
                }
            }
            if visible.isEmpty {
                VStack(spacing: 8) {
                    Text(monitor.ready ? "No matching items" : "Finding your apps…").font(.headline)
                    if monitor.ready { Text("Try a different search or category.").foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity).padding(.vertical, 32)
            }
        }
    }
    private func suggestionRow(_ workload: Workload, subtitle: String, symbol: String) -> some View {
        Button { path.append(workload) } label: {
            OpenRow(name: workload.name, subtitle: subtitle, icon: SymbolTile(symbol: symbol))
        }.buttonStyle(.plain).help("Review current readings for \(workload.name)")
            .overlay(alignment: .top) { Rectangle().fill(theme.line).frame(height: 1) }
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
    var size: CGFloat = 32
    @Environment(\.brushed) private var theme
    var body: some View {
        Group {
            if let path = workload.appPath { Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable() }
            else { Image(systemName: workload.kind.symbol).resizable().scaledToFit().padding(size * 0.22).foregroundStyle(theme.sub) }
        }.frame(width: size, height: size)
    }
}
