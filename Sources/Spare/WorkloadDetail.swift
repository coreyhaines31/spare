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
            VStack(alignment: .leading, spacing: 20) {
                Button(action: back) { Label("All apps & projects", systemImage: "chevron.left") }.buttonStyle(.plain).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    WorkloadIcon(workload: workload)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(workload.name).font(.title2.bold()).textSelection(.enabled)
                        Text(workload.subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Label(DisplayFormat.memory(workload.memory), systemImage: "memorychip")
                    Spacer()
                    Label("\(DisplayFormat.percent(workload.cpu)) CPU", systemImage: "cpu")
                }.font(.headline).padding(14).background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                Text(review != nil ? "Reviewing a fixed set of processes. New processes won’t be included." : latest == nil ? "This item is no longer detected. Readings below are its last captured values." : "Live readings · Updated every 3 seconds").font(.caption).foregroundStyle(.secondary)
                section("What is this?", workload.explanation)
                if let path = workload.projectPath {
                    section("Project", DisplayFormat.homePath(path))
                    Button("Show project in Finder") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path) }
                }
                if !workload.ports.isEmpty {
                    section("Local server ports", workload.ports.map(String.init).joined(separator: ", ") + " · Listening on this Mac")
                }
                section("What happens if I close it?", workload.consequence)
                if review == nil && workload.sessions.count > 1 {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Individual sessions").font(.headline)
                        Text("Review one session to leave the others running.").font(.caption).foregroundStyle(.secondary)
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
                        Text("Close \(workload.name)?").font(.headline)
                        Text(workload.appIdentity != nil ? "Spare will ask this app to quit normally. Save any work first." :
                            "Spare will ask these \(workload.processes.count) processes to stop. Running agent tasks or unsaved in-memory work may be interrupted. Nothing is force-killed.")
                        HStack {
                            Button("Cancel") { review = nil }
                            Spacer()
                            Button(workload.appIdentity != nil ? "Request quit" : "Stop these processes", role: .destructive) {
                                monitor.stop(workload)
                                back()
                            }.buttonStyle(.borderedProminent).tint(.orange).disabled(monitor.error != nil)
                        }
                    }.padding(16).background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                } else if workload.canStop && latest != nil {
                    Button(workload.appIdentity != nil ? "Review & quit app…" : "Review & stop processes…") { review = latest }
                        .buttonStyle(.borderedProminent).tint(.green)
                } else {
                    Text(latest == nil ? "There’s nothing to stop in this reading. Return to the list to see what’s running now." : "Spare protects this item from stop requests. You can inspect its technical details below.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let path = workload.appPath {
                    Button("Open app") { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
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
            }.padding(20)
        }
    }
    private func section(_ heading: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(heading).font(.headline)
            Text(text).font(.system(size: 13)).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }
}
