import Foundation

public extension Workload {
    var sessions: [Workload] {
        guard kind == .agent || kind == .development else { return [] }
        let byPID = Dictionary(uniqueKeysWithValues: processes.map { ($0.identity.pid, $0) })
        var members: [ProcessIdentity: [ProcessRecord]] = [:]
        for process in processes {
            var root = process
            var seen: Set<Int32> = [root.identity.pid]
            while let parent = byPID[root.parent], !seen.contains(parent.identity.pid) {
                seen.insert(parent.identity.pid)
                root = parent
            }
            members[root.identity, default: []].append(process)
        }
        return members.map { identity, records in
            var session = self
            session.id = "\(id):session:\(identity.pid):\(identity.started)"
            session.processes = records
            let date = Date(timeIntervalSince1970: Double(identity.started) / 1_000_000)
            session.subtitle = "Started \(date.formatted(date: .abbreviated, time: .shortened)) · \(records.count) processes"
            return session
        }.sorted { $0.processes.map(\.identity.started).min() ?? 0 < $1.processes.map(\.identity.started).min() ?? 0 }
    }

    func current(in workloads: [Workload]) -> Workload? {
        workloads.first(where: { $0.id == id }) ?? workloads.flatMap(\.sessions).first(where: { $0.id == id })
    }
}

public struct StopFollowUp {
    public enum Result: Equatable {
        case waiting, noLongerVisible, stillRunning(Int)
    }
    public let identities: Set<ProcessIdentity>
    public let deadline: TimeInterval

    public init(identities: Set<ProcessIdentity>, now: TimeInterval) {
        self.identities = identities
        deadline = now + 15
    }

    public func result(visible: Set<ProcessIdentity>, now: TimeInterval) -> Result {
        let remaining = identities.intersection(visible).count
        if remaining == 0 { return .noLongerVisible }
        return now >= deadline ? .stillRunning(remaining) : .waiting
    }
}
