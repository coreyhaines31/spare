import Foundation

/// A separate app session that nothing is driving anymore, such as a browser an automation tool left open.
public struct LeftoverSession {
    public let app: Workload
    public let process: ProcessRecord
    public let origin: SessionOrigin
    /// The session's own memory plus the helpers it started.
    public let memory: UInt64
}

public enum Leftovers {
    /// Leftover browser sessions across every browser, largest first. Only browsers count: other apps run extra copies
    /// of their own executable as services, which aren't sessions anyone opened.
    /// `arguments` reads a process's launch arguments; `apps` names the running apps by process ID.
    public static func find(_ workloads: [Workload], records: [Int32: ProcessRecord], apps: [Int32: String],
                            arguments: @escaping (ProcessIdentity) -> [String],
                            project: @escaping (String) -> String = { $0 }) -> [LeftoverSession] {
        let argumentsByPID: (Int32) -> [String] = { pid in records[pid].map { arguments($0.identity) } ?? [] }
        return workloads.filter { $0.kind == .application && ProcessClassifier.isBrowser($0.name) }.flatMap { app -> [LeftoverSession] in
            let mainPath = app.processes.first { $0.identity == app.appIdentity }?.path ?? ""
            let children = Dictionary(grouping: app.processes, by: \.parent)
            return app.processes.compactMap { process in
                guard process.identity != app.appIdentity,
                      HelperRole.classify(name: process.name, arguments: arguments(process.identity), isMain: false,
                                          path: process.path, mainPath: mainPath) == .session else { return nil }
                let origin = SessionOrigin.find(for: process, in: records, apps: apps, arguments: argumentsByPID, project: project)
                guard origin.isUnattended else { return nil }
                return LeftoverSession(app: app, process: process, origin: origin,
                                       memory: memory(of: process, children: children))
            }
        }.sorted { $0.memory > $1.memory }
    }

    private static func memory(of process: ProcessRecord, children: [Int32: [ProcessRecord]]) -> UInt64 {
        var total: UInt64 = 0
        var queue = [process]
        var seen: Set<Int32> = []
        while let next = queue.popLast() {
            guard seen.insert(next.identity.pid).inserted else { continue }
            total += next.memory
            queue += children[next.identity.pid] ?? []
        }
        return total
    }
}

public extension SessionOrigin {
    /// Who is asking, for a request made from the command line, such as "Claude in website" or "Terminal".
    var requesterName: String? {
        switch self {
        case .agent(let name, let folder), .tool(let name, let folder): return folder.isEmpty ? name : "\(name) in \(folder)"
        case .app(let name): return name
        default: return nil
        }
    }
}
