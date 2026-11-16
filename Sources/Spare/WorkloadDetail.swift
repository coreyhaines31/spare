import SwiftUI
import SpareCore
import PanelKit

struct WorkloadDetail: View {
    let selection: Workload
    @ObservedObject var monitor: Monitor
    let back: () -> Void
    let select: (Workload) -> Void
    @State private var review: Workload?
    private var latest: Workload? { selection.current(in: monitor.workloads) }
    private var workload: Workload { review ?? latest ?? selection }
    private var activity: AgentActivity? { latest?.activity(in: monitor.agentActivity) }
    /// The reviewed processes' activity now, so a stop review warns if they start working.
    private var liveActivity: AgentActivity? { workload.activity(in: monitor.agentActivity) }
    @Environment(\.panelTheme) private var theme
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    WorkloadIcon(workload: workload)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(workload.name).font(PanelFont.condensed(22, .semibold)).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(workload.subtitle).font(PanelFont.body(11.5)).foregroundStyle(theme.sub)
                        if let activity { ActivityBadge(activity: activity) }
                    }
                }.padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 10)
                HStack(spacing: 8) {
                    ReadingTile("Memory", value: DisplayFormat.memory(workload.memory))
                    ReadingTile("CPU", value: DisplayFormat.percent(workload.cpu))
                }.fixedSize(horizontal: false, vertical: true).padding(.horizontal, 14)
                PanelNote(review != nil ? "Reviewing a fixed set of processes. New processes won’t be included." : latest == nil ? "This item is no longer detected. Readings below are its last captured values." : "Live readings · Updated every 3 seconds")
                    .padding(.vertical, 8)
                if review == nil && workload.kind == .application && workload.processes.count > 1 {
                    AppHelpersSection(workload: workload, monitor: monitor)
                }
                TextSection(heading: "About", text: workload.explanation)
                if DockerSettings.isDocker(workload) { dockerSection }
                if let path = workload.projectPath {
                    TextSection(heading: "Project", text: DisplayFormat.homePath(path))
                    Button("Show in Finder") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path) }
                        .buttonStyle(.panelQuietLink).padding(.horizontal, 14).padding(.bottom, 10)
                }
                if let command = workload.commandSummary(arguments: ProcessArguments.cached(for:)) {
                    TextSection(heading: "Command", text: command)
                }
                if !workload.ports.isEmpty {
                    TextSection(heading: "Local server ports", text: workload.ports.map(String.init).joined(separator: ", ") + " · Listening on this Mac")
                    ForEach(workload.webPorts, id: \.self) { port in
                        if let url = URL(string: "http://localhost:\(port)") {
                            Link(String("Open localhost:\(port)"), destination: url).buttonStyle(.panelQuietLink)
                                .padding(.horizontal, 14).padding(.bottom, 8)
                        }
                    }
                }
                TextSection(heading: "Before closing", text: workload.consequence)
                if review == nil && workload.sessions.count > 1 {
                    SectionHeader("Sessions")
                    PanelNote("Choose one session to leave the others running.").padding(.bottom, 4)
                    ForEach(workload.sessions) { session in
                        Button { select(session) } label: {
                            Row(session.subtitle, subtitle: "\(DisplayFormat.memory(session.memory)) · \(DisplayFormat.percent(session.cpu)) CPU",
                                options: .chevron) {
                                if let activity = session.activity(in: monitor.agentActivity) { ActivityBadge(activity: activity) }
                            }
                        }.buttonStyle(.plain)
                    }
                }
                stopControls.padding(.horizontal, 14).padding(.vertical, 10)
                    .overlay(alignment: .top) { Rectangle().fill(theme.line).frame(height: 1) }
                if review == nil, let trend = monitor.memoryTrends[selection.id] {
                    Disclosure("Memory history", subtitle: trend.summary) {
                        MemoryTrendView(trend: trend).padding(.horizontal, 14).padding(.bottom, 10)
                    }.overlay(alignment: .top) { Rectangle().fill(theme.line).frame(height: 1) }
                }
                Disclosure("Technical details · \(workload.processes.count) process\(workload.processes.count == 1 ? "" : "es")") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(workload.processes, id: \.identity) { process in
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(process.name) · PID \(process.identity.pid)").font(PanelFont.body(11.5, .semibold))
                                Text(process.path.isEmpty ? "Executable path unavailable" : process.path).font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(theme.ink2).textSelection(.enabled)
                                Text("\(DisplayFormat.memory(process.memory)) · \(DisplayFormat.percent(process.cpu)) CPU").font(PanelFont.body(11)).foregroundStyle(theme.sub)
                            }
                        }
                    }.padding(.horizontal, 14).padding(.bottom, 12)
                }.overlay(alignment: .top) { Rectangle().fill(theme.line).frame(height: 1) }
            }
        }
    }
    /// Review, then quit or stop; or say why there's nothing to stop. Open app sits beside it.
    @ViewBuilder private var stopControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            if review != nil {
                // Live, not frozen with the review: whether it's mid-task can change while you decide.
                ConfirmBox(title: workload.appIdentity != nil ? "Quit \(workload.name)?" : "Stop these tasks?",
                           message: workload.appIdentity != nil ? "Spare will ask this app to quit normally. Save any work first." :
                            "Spare will ask these \(workload.processes.count) processes to stop. Running agent tasks or unsaved in-memory work may be interrupted. Nothing is force-killed.",
                           warning: liveActivity?.stopWarning(agent: workload.name),
                           actionTitle: workload.appIdentity != nil ? "Quit app" : "Stop tasks", isActionDisabled: monitor.error != nil,
                           cancel: { review = nil }, confirm: {
                    monitor.stop(workload)
                    back()
                })
            } else if !(workload.canStop && latest != nil) {
                PanelNote(latest == nil ? "There’s nothing to stop in this reading. Return to the list to see what’s running now." : "Spare protects this item from stop requests. You can inspect its technical details below.")
                    .padding(.horizontal, -14)
            }
            HStack(spacing: 8) {
                if review == nil && workload.canStop && latest != nil {
                    Button(workload.appIdentity != nil ? "Review quit…" : workload.sessions.count > 1 ? "Review all sessions…" : "Review stop…") { review = latest }
                        .buttonStyle(.panelSecondary)
                }
                if let path = workload.appPath {
                    Button("Open app") { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }.buttonStyle(.panelSecondary)
                }
            }
        }
    }
    private var dockerSection: some View {
        let physical = monitor.samples.last?.physical ?? ProcessInfo.processInfo.physicalMemory
        let limit = DockerSettings.memoryLimit(physical: physical)
        return VStack(alignment: .leading, spacing: 0) {
            TextSection(heading: "Docker’s memory", text: "Docker Desktop runs your containers inside one Linux virtual machine. That VM can use up to \(DisplayFormat.memory(limit.bytes))\(limit.isDefault ? ", Docker’s default of half your Mac’s memory" : ""). Stopping containers you don’t need frees memory, and Docker’s Resource Saver shuts the VM down after a few idle minutes.")
            PanelNote("To lower the limit: Docker Desktop → Settings → Resources → Advanced.").padding(.bottom, 8)
            if let docker = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.docker.docker") {
                Button("Open Docker Desktop") { NSWorkspace.shared.open(docker) }.buttonStyle(.panelSecondary)
                    .padding(.horizontal, 14).padding(.bottom, 10)
            }
        }
    }
}
