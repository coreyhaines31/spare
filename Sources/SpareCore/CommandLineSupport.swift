import Foundation

public extension WorkloadKind {
    /// The kind as the command line names it, matching the panel's filters.
    var commandName: String {
        switch self {
        case .application: return "app"
        case .development: return "project"
        case .agent: return "agent"
        case .system: return "macos"
        case .background: return "background"
        }
    }

    var commandLabel: String {
        switch self {
        case .application: return "App"
        case .development: return "Project"
        case .agent: return "Agent"
        case .system: return "macOS"
        case .background: return "Background"
        }
    }
}

/// Finds the one workload a person or agent means by a name, id, or process ID.
public enum WorkloadLookup {
    public enum Result {
        case found(Workload)
        case ambiguous([Workload])
        case notFound
    }

    /// Tries an exact id, a process ID, an exact name, a name prefix, then a search match, stopping at the first step with any result.
    public static func find(_ query: String, in workloads: [Workload]) -> Result {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return .notFound }
        let steps: [(Workload) -> Bool] = [
            { $0.id == query },
            { workload in Int32(query).map { pid in workload.processes.contains { $0.identity.pid == pid } } ?? false },
            { $0.name.caseInsensitiveCompare(query) == .orderedSame },
            { $0.name.lowercased().hasPrefix(query.lowercased()) },
            { $0.matches(query) }
        ]
        for step in steps {
            let matches = workloads.filter(step)
            if matches.count == 1 { return .found(matches[0]) }
            if matches.count > 1 { return .ambiguous(matches) }
        }
        return .notFound
    }
}

/// One row of `spare list`, also used inside other JSON output.
public struct WorkloadSummary: Codable, Equatable {
    public var id: String
    public var name: String
    public var kind: String
    public var subtitle: String
    public var memoryBytes: UInt64
    public var memory: String
    public var cpuPercent: Double
    public var processCount: Int
    public var ports: [UInt16]
    public var canQuit: Bool
    public var projectPath: String?
    public var appPath: String?
    public var command: String?
    public var note: String?

    public init(_ workload: Workload, command: String? = nil, note: String? = nil) {
        id = workload.id
        name = workload.name
        kind = workload.kind.commandName
        subtitle = workload.subtitle
        memoryBytes = workload.memory
        memory = DisplayFormat.memory(workload.memory)
        cpuPercent = (workload.cpu * 10).rounded() / 10
        processCount = workload.processes.count
        ports = workload.ports
        canQuit = workload.canStop
        projectPath = workload.projectPath
        appPath = workload.appPath
        self.command = command
        self.note = note
    }
}

/// The overall reading behind `spare status`.
public struct StatusSummary: Codable, Equatable {
    public var title: String
    public var message: String
    public var cpuPercent: Double
    public var cpuAvailablePercent: Double
    public var memoryPressure: String
    public var memoryUsedBytes: UInt64
    public var memoryTotalBytes: UInt64
    public var memoryUsed: String
    public var memoryTotal: String
    public var swapBytes: UInt64

    public init(sample: SystemSample, ready: Bool) {
        let health = Health(samples: [sample], ready: ready)
        title = health.title
        message = health.message
        cpuPercent = (sample.cpu * 10).rounded() / 10
        cpuAvailablePercent = ((100 - sample.cpu) * 10).rounded() / 10
        memoryPressure = sample.pressure.rawValue
        memoryUsedBytes = sample.memory
        memoryTotalBytes = sample.physical
        memoryUsed = DisplayFormat.memory(sample.memory)
        memoryTotal = DisplayFormat.memory(sample.physical)
        swapBytes = sample.swap
    }

    /// 2 for a memory pressure warning and 3 for critical, so scripts can check pressure without parsing.
    public var exitCode: Int32 {
        switch memoryPressure {
        case MemoryPressure.warning.rawValue: return 2
        case MemoryPressure.critical.rawValue: return 3
        default: return 0
        }
    }
}

/// Lines up columns for terminal output.
public enum TextTable {
    public static func render(_ rows: [[String]], rightAligned: Set<Int> = [], maxWidth: [Int: Int] = [:]) -> String {
        let clipped = rows.map { row in
            row.enumerated().map { index, cell in
                guard let limit = maxWidth[index], cell.count > limit else { return cell }
                return String(cell.prefix(limit - 1)) + "…"
            }
        }
        let columns = clipped.map(\.count).max() ?? 0
        let widths = (0..<columns).map { column in clipped.map { column < $0.count ? $0[column].count : 0 }.max() ?? 0 }
        return clipped.map { row in
            row.enumerated().map { index, cell in
                let padding = String(repeating: " ", count: widths[index] - cell.count)
                if rightAligned.contains(index) { return padding + cell }
                return index == row.count - 1 ? cell : cell + padding
            }.joined(separator: "  ")
        }.joined(separator: "\n")
    }
}
