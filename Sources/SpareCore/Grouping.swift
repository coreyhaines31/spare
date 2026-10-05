import Foundation

public enum WorkloadGrouper {
    public static func group(_ processes: [ProcessRecord], apps: [AppRecord],
                             project: (String) -> String = { $0 }) -> [Workload] {
        let byPID = Dictionary(uniqueKeysWithValues: processes.map { ($0.identity.pid, $0) })
        let appByPID = Dictionary(apps.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        let orderedApps = apps.sorted { $0.path.count < $1.path.count }
        var groups: [String: Workload] = [:]
        for process in processes {
            let lineage = ancestors(process, in: byPID)
            let bundledApp = orderedApps.first { process.path.hasPrefix($0.path + "/") }
            var workload: Workload
            if let app = bundledApp {
                workload = appGroup(app, processes: byPID)
            } else if let owner = (lineage.first(where: { ProcessClassifier.developerKind($0) == .agent }) ??
                        lineage.first(where: { ProcessClassifier.developerKind($0) != nil })),
                      let kind = ProcessClassifier.developerKind(owner) {
                workload = developerGroup(owner, kind: kind, project: project(owner.directory))
            } else if let app = lineage.compactMap({ appByPID[$0.identity.pid] }).first {
                workload = appGroup(app, processes: byPID)
            } else {
                let name = process.name.isEmpty ? "Unidentified task" : process.name
                workload = Workload(id: "process:\(process.identity.pid):\(process.identity.started)", name: name,
                                    subtitle: "Background task · ownership unknown",
                                    explanation: "Spare can measure this task, but hasn't identified the app or project responsible. Its executable path is shown below.",
                                    consequence: "Inspect this task in Activity Monitor before making changes.", kind: .background,
                                    processes: [], canStop: false)
            }
            if groups[workload.id] == nil { groups[workload.id] = workload }
            groups[workload.id]?.processes.append(process)
        }
        return groups.values.map { original in
            var group = original
            if group.kind != .background {
                let count = group.processes.count
                group.subtitle = "\(group.kind.label) · \(count) process\(count == 1 ? "" : "es")"
                if !group.ports.isEmpty {
                    group.subtitle += " · port " + group.ports.prefix(3).map(String.init).joined(separator: ", ")
                }
            }
            return group
        }.sorted { $0.memory > $1.memory }
    }

    private static func ancestors(_ process: ProcessRecord, in records: [Int32: ProcessRecord]) -> [ProcessRecord] {
        var result = [process]
        var seen: Set<Int32> = [process.identity.pid]
        var parent = process.parent
        while let record = records[parent], !seen.contains(parent), result.count < 32 {
            seen.insert(parent)
            result.append(record)
            parent = record.parent
        }
        return result
    }

    private static func appGroup(_ app: AppRecord, processes: [Int32: ProcessRecord]) -> Workload {
        let copy = ProcessClassifier.appExplanation(app.name)
        return Workload(id: "app:\(app.path)", name: app.name, subtitle: "App and related helpers",
                        explanation: copy.0, consequence: copy.1, kind: .application,
                        appPath: app.path, appIdentity: processes[app.pid]?.identity,
                        processes: [], canStop: app.canQuit && processes[app.pid] != nil)
    }

    private static func developerGroup(_ process: ProcessRecord, kind: WorkloadKind, project: String) -> Workload {
        let folder = project.isEmpty ? "Unknown project" : URL(fileURLWithPath: project).lastPathComponent
        let agent = ProcessClassifier.agentName(process)
        let name = kind == .agent ? "\(agent) · \(folder)" : folder
        let scope = project.isEmpty ? "pid:\(process.identity.pid)" : project
        let identity = kind == .agent ? "\(scope):\(agent)" : scope
        let explanation = kind == .agent
            ? "An AI tool running locally for this folder. It may be working, waiting for a model, or running tools. Low CPU does not mean the session is finished."
            : "Development tools running from this folder, such as local website previews, builds, and watchers. Listening ports appear below when detected."
        let consequence = kind == .agent
            ? "Stopping this group interrupts its agent sessions and running tools. Finish or save your work in the agent first."
            : "Stopping this group interrupts its local servers, builds, and watchers. Local previews may go offline. Source files are not deleted."
        return Workload(id: "\(kind.rawValue):\(identity)", name: name, subtitle: kind.label,
                        explanation: explanation, consequence: consequence, kind: kind,
                        projectPath: project.isEmpty ? nil : project, processes: [], canStop: true)
    }
}
