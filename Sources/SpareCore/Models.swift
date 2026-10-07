import Foundation

public struct ProcessIdentity: Hashable, Codable {
    public let pid: Int32
    public let started: UInt64
    public init(pid: Int32, started: UInt64) {
        self.pid = pid
        self.started = started
    }
}

public struct ProcessRecord: Codable {
    public var identity: ProcessIdentity
    public var parent: Int32
    public var name: String
    public var path: String
    public var directory: String
    public var memory: UInt64
    public var cpu: Double
    public var ports: [UInt16]

    public init(pid: Int32, started: UInt64 = 1, parent: Int32 = 1, name: String, path: String,
                directory: String = "", memory: UInt64 = 0, cpu: Double = 0, ports: [UInt16] = []) {
        identity = ProcessIdentity(pid: pid, started: started)
        self.parent = parent
        self.name = name
        self.path = path
        self.directory = directory
        self.memory = memory
        self.cpu = cpu
        self.ports = ports
    }
}

public struct AppRecord {
    public let pid: Int32
    public let name: String
    public let path: String
    public let canQuit: Bool
    public init(pid: Int32, name: String, path: String, canQuit: Bool) {
        self.pid = pid
        self.name = name
        self.path = path
        self.canQuit = canQuit
    }
}

public enum WorkloadKind: String, Codable, CaseIterable {
    case application, development, agent, system, background
    public var label: String {
        switch self {
        case .application: return "App"
        case .development: return "Development"
        case .agent: return "AI agent"
        case .system: return "macOS"
        case .background: return "Background"
        }
    }
    public var symbol: String {
        switch self {
        case .application: return "app.fill"
        case .development: return "terminal.fill"
        case .agent: return "sparkles"
        case .system: return "apple.logo"
        case .background: return "gearshape.fill"
        }
    }
}

public struct Workload: Identifiable, Codable {
    public var id: String
    public var name: String
    public var subtitle: String
    public var explanation: String
    public var consequence: String
    public var kind: WorkloadKind
    public var appPath: String?
    public var appIdentity: ProcessIdentity?
    public var projectPath: String?
    public var processes: [ProcessRecord]
    public var canStop: Bool
    public var memory: UInt64 { processes.reduce(0) { $0 + $1.memory } }
    public var cpu: Double { processes.reduce(0) { $0 + $1.cpu } }
    public var ports: [UInt16] { Array(Set(processes.flatMap(\.ports))).sorted() }
}

public enum MemoryPressure: String, Codable {
    case normal, warning, critical, unknown
    public init(level: Int32) {
        switch level {
        case 1: self = .normal
        case 2: self = .warning
        case 4: self = .critical
        default: self = .unknown
        }
    }
}

public struct SystemSample: Codable {
    public var date: Date
    public var cpu: Double
    public var memory: UInt64
    public var physical: UInt64
    public var compressed: UInt64
    public var swap: UInt64
    public var pressure: MemoryPressure
    public init(date: Date = Date(), cpu: Double = 0, memory: UInt64 = 0, physical: UInt64 = 0,
                compressed: UInt64 = 0, swap: UInt64 = 0, pressure: MemoryPressure = .unknown) {
        self.date = date
        self.cpu = cpu
        self.memory = memory
        self.physical = physical
        self.compressed = compressed
        self.swap = swap
        self.pressure = pressure
    }
}

public enum DisplayFormat {
    public static func memory(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .memory)
    }
    public static func percent(_ value: Double) -> String { String(format: "%.0f%%", value) }
    public static func homePath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}
