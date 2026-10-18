import Foundation

/// Whether an agent looks mid-task, so closing it doesn't cut off a reply.
public enum AgentActivity: String, Codable {
    /// The agent reports it's working on a reply or running a tool.
    case working
    /// The agent reports it's waiting for you.
    case waiting
    /// No report, but it used CPU in the last few seconds.
    case active
    /// No report, and no recent CPU.
    case quiet

    public var label: String {
        switch self {
        case .working: "Working"
        case .waiting: "Waiting for you"
        case .active: "Active"
        case .quiet: "Quiet"
        }
    }

    public var isBusy: Bool { self == .working || self == .active }

    /// A warning for the stop review, or nil when nothing looks mid-task.
    public func stopWarning(agent: String) -> String? {
        switch self {
        case .working: "\(agent) is working right now. Stopping interrupts it mid-task. Let it finish, or stop it in the agent first."
        case .active: "\(agent) used CPU in the last few seconds, so it may be mid-task."
        case .waiting, .quiet: nil
        }
    }

    /// One reading for a group of agent processes. A report from the agent outranks an estimate from CPU.
    public static func combine(_ activities: [AgentActivity]) -> AgentActivity? {
        if activities.contains(.working) { return .working }
        if activities.contains(.waiting) { return .waiting }
        if activities.contains(.active) { return .active }
        return activities.isEmpty ? nil : .quiet
    }
}

/// Claude Code writes its status to ~/.claude/sessions/<pid>.json while it runs.
public enum ClaudeSessionStatus {
    public struct Entry: Equatable {
        public var busy: Bool
        /// When the session started. A session can't start before its process, which catches a reused process ID.
        public var started: Date
    }

    public static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/sessions")
    }

    public static func read(directory: URL = directory) -> [Int32: Entry] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var entries: [Int32: Entry] = [:]
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file), let (pid, entry) = parse(data) { entries[pid] = entry }
        }
        return entries
    }

    static func parse(_ data: Data) -> (Int32, Entry)? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pid = (object["pid"] as? NSNumber)?.int32Value,
              let started = (object["startedAt"] as? NSNumber)?.doubleValue else { return nil }
        let busy: Bool
        switch object["status"] as? String {
        case "busy": busy = true
        case "idle": busy = false
        default: return nil
        }
        return (pid, Entry(busy: busy, started: Date(timeIntervalSince1970: started / 1000)))
    }
}

/// Remembers when each agent process last used CPU, and turns that plus Claude Code's reports into an activity.
public final class AgentActivityTracker {
    /// A share of one core. An agent waiting for input sits near zero; one drawing a spinner or running a tool doesn't.
    static let activeCoreShare = 3.0
    /// How long an agent counts as active after its last busy reading.
    static let window: TimeInterval = 10
    private var lastActive: [ProcessIdentity: TimeInterval] = [:]
    private let cores: Double

    public init(cores: Double = Double(ProcessInfo.processInfo.activeProcessorCount)) { self.cores = cores }

    public func reset() { lastActive = [:] }

    /// Activity for each agent process. CPU readings only count once `ready`.
    public func record(_ processes: [ProcessRecord], ready: Bool, claude: [Int32: ClaudeSessionStatus.Entry],
                       now: TimeInterval) -> [ProcessIdentity: AgentActivity] {
        var activities: [ProcessIdentity: AgentActivity] = [:]
        var seen: [ProcessIdentity: TimeInterval] = [:]
        for process in processes where ProcessClassifier.developerKind(process) == .agent {
            let identity = process.identity
            if let last = lastActive[identity] { seen[identity] = last }
            if ready && process.cpu * cores >= Self.activeCoreShare { seen[identity] = now }
            if let entry = claude[identity.pid],
               entry.started.timeIntervalSince1970 * 1_000_000 + 5_000_000 >= Double(identity.started) {
                activities[identity] = entry.busy ? .working : .waiting
            } else if let last = seen[identity], now - last <= Self.window {
                activities[identity] = .active
            } else if ready {
                activities[identity] = .quiet
            }
        }
        lastActive = seen
        return activities
    }
}

public extension Workload {
    /// Nil for anything that isn't an agent, or before there's a reading.
    func activity(in activities: [ProcessIdentity: AgentActivity]) -> AgentActivity? {
        guard kind == .agent else { return nil }
        return AgentActivity.combine(processes.compactMap { activities[$0.identity] })
    }
}
