import Foundation

public enum WorkloadFilter: String, CaseIterable {
    case all = "All", apps = "Apps", projects = "Projects", agents = "Agents"

    public func includes(_ workload: Workload) -> Bool {
        switch self {
        case .all: return true
        case .apps: return workload.kind == .application
        case .projects: return workload.kind == .development
        case .agents: return workload.kind == .agent
        }
    }
}

public extension Workload {
    func matches(_ query: String) -> Bool {
        let words = query.split(whereSeparator: \.isWhitespace)
        let searchable = ([name, projectPath ?? "", kind.label] + ports.map(String.init)).joined(separator: " ")
        return words.allSatisfy { searchable.localizedCaseInsensitiveContains($0) }
    }
}

public struct ReviewSuggestion {
    public let workload: Workload
    public let explanation: String

    public static func make(workloads: [Workload], samples: [SystemSample], ready: Bool) -> ReviewSuggestion? {
        guard ready, Health(samples: samples, ready: ready).level > 0, let sample = samples.last else { return nil }
        let memoryConcern = sample.pressure == .warning || sample.pressure == .critical
        let candidates = workloads.filter { $0.canStop }
        guard let largest = candidates.max(by: { memoryConcern ? $0.memory < $1.memory : $0.cpu < $1.cpu }),
              memoryConcern ? largest.memory > 0 : largest.cpu > 1 else { return nil }
        let resource = memoryConcern ? "\(DisplayFormat.memory(largest.memory)) of memory" : "\(DisplayFormat.percent(largest.cpu)) of your Mac’s CPU"
        return ReviewSuggestion(workload: largest,
            explanation: "\(largest.name) is using \(resource), the most among items Spare can help close. If you’re finished with it, review what closing it would affect.")
    }
}
