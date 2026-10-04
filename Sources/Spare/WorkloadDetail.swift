import SwiftUI
import SpareCore

struct WorkloadDetail: View {
    let selection: Workload
    @ObservedObject var monitor: Monitor
    let back: () -> Void
    let select: (Workload) -> Void
    @State private var review: Workload?
    private var latest: Workload? { selection.current(in: monitor.workloads) }
    private var workload: Workload { review ?? latest ?? selection }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    WorkloadIcon(workload: workload)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(workload.name).font(.title2.weight(.semibold)).textSelection(.enabled)
                        Text(workload.subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Label(DisplayFormat.memory(workload.memory), systemImage: "memorychip")
                    Spacer()
                    Label("\(DisplayFormat.percent(workload.cpu)) CPU", systemImage: "cpu")
                }.font(.body).padding(.vertical, 10)
                Divider()
                Text(review != nil ? "Reviewing a fixed set of processes. New processes won’t be included." : latest == nil ? "This item is no longer detected. Readings below are its last captured values." : "Live readings · Updated every 3 seconds").font(.caption).foregroundStyle(.secondary)
                section("About", workload.explanation)
                if let path = workload.projectPath {
                    section("Project", DisplayFormat.homePath(path))
                    Button("Show in Finder") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path) }.buttonStyle(.link)
                }
                if !workload.ports.isEmpty {
                    section("Local server ports", workload.ports.map(String.init).joined(separator: ", ") + " · Listening on this Mac")
                }
                section("Before closing", workload.consequence)
                if review == nil && workload.sessions.count > 1 {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Sessions").font(.headline)
                        Text("Choose one session to leave the others running.").font(.caption).foregroundStyle(.secondary)
                        ForEach(workload.sessions) { session in
                            Button { select(session) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(session.subtitle).font(.caption)
                                        Text("\(DisplayFormat.memory(session.memory)) · \(DisplayFormat.percent(session.cpu)) CPU").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                }.padding(10).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                }
                if review != nil {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(workload.appIdentity != nil ? "Quit \(workload.name)?" : "Stop these tasks?").font(.headline)
                        Text(workload.appIdentity != nil ? "Spare will ask this app to quit normally. Save any work first." :
                            "Spare will ask these \(workload.processes.count) processes to stop. Running agent tasks or unsaved in-memory work may be interrupted. Nothing is force-killed.")
                        HStack {
                            Button("Cancel") { review = nil }.keyboardShortcut(.cancelAction)
                            Spacer()
                            Button(workload.appIdentity != nil ? "Quit app" : "Stop tasks", role: .destructive) {
                                monitor.stop(workload)
                                back()
                            }.buttonStyle(.borderedProminent).tint(.red).disabled(monitor.error != nil)
                        }
                    }.padding(12).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                } else if workload.canStop && latest != nil {
                    Button(workload.appIdentity != nil ? "Review quit…" : workload.sessions.count > 1 ? "Review all sessions…" : "Review stop…") { review = latest }
                        .buttonStyle(.bordered)
                } else {
                    Text(latest == nil ? "There’s nothing to stop in this reading. Return to the list to see what’s running now." : "Spare protects this item from stop requests. You can inspect its technical details below.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let path = workload.appPath {
                    Button("Open app") { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
                }
                if review == nil, let trend = monitor.memoryTrends[selection.id] {
                    DisclosureGroup("Memory history") { MemoryTrendView(trend: trend).padding(.top, 8) }
                }
                DisclosureGroup("Technical details · \(workload.processes.count) processes") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(workload.processes, id: \.identity) { process in
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(process.name) · PID \(process.identity.pid)").font(.caption.bold())
                                Text(process.path.isEmpty ? "Executable path unavailable" : process.path).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                                Text("\(DisplayFormat.memory(process.memory)) · \(DisplayFormat.percent(process.cpu)) CPU").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }.padding(.top, 10)
                }
            }.padding(16)
        }
    }
    private func section(_ heading: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(heading).font(.headline)
            Text(text).font(.system(size: 13)).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }
}
