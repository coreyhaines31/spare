import SwiftUI
import SpareCore

struct WorkloadDetail: View {
    let workload: Workload
    @ObservedObject var monitor: Monitor
    let back: () -> Void
    @State private var reviewing = false
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
                Text("Readings captured when you opened this view.").font(.caption).foregroundStyle(.secondary)
                section("What is this?", workload.explanation)
                if let path = workload.projectPath {
                    section("Project", DisplayFormat.homePath(path))
                    Button("Show project in Finder") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path) }
                }
                if !workload.ports.isEmpty {
                    section("Local server ports", workload.ports.map(String.init).joined(separator: ", ") + " · Listening on this Mac")
                }
                section("What happens if I close it?", workload.consequence)
                if reviewing {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Close \(workload.name)?").font(.headline)
                        Text(workload.appIdentity != nil ? "Spare will ask this app to quit normally. Save any work first." :
                            "Spare will ask these \(workload.processes.count) processes to stop. Running agent tasks or unsaved in-memory work may be interrupted. Nothing is force-killed.")
                        HStack {
                            Button("Cancel") { reviewing = false }
                            Spacer()
                            Button(workload.appIdentity != nil ? "Request quit" : "Stop these processes", role: .destructive) {
                                monitor.stop(workload)
                                back()
                            }.buttonStyle(.borderedProminent).tint(.orange)
                        }
                    }.padding(16).background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                } else if workload.canStop {
                    Button(workload.appIdentity != nil ? "Review & quit app…" : "Review & stop processes…") { reviewing = true }
                        .buttonStyle(.borderedProminent).tint(.green)
                } else {
                    Text("Spare doesn’t offer a stop button for this process because it can’t safely identify a user app to close.")
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
