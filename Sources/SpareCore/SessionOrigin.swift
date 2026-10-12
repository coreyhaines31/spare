import Foundation

/// A short, recognizable name for a command, such as "next dev", "vite", or "agent-browser".
public enum CommandSummary {
    private static let interpreters: Set<String> = ["node", "bun", "deno", "ruby", "php", "java", "env", "sh", "bash", "zsh"]

    private static let runners: [[String]] = [["npm", "exec"], ["pnpm", "dlx"], ["npx"], ["bunx"], ["uvx"]]

    public static func make(_ arguments: [String]) -> String? {
        // Some tools rewrite their process title into one string, such as "npm exec clipatra@latest serve".
        var arguments = arguments
        if let first = arguments.first, first.contains(" "), !first.hasPrefix("/") {
            arguments = first.split(separator: " ").map(String.init) + arguments.dropFirst()
        }
        if let runner = runners.first(where: { arguments.starts(with: $0) }) {
            arguments = Array(arguments.dropFirst(runner.count))
        }
        var rest = arguments.drop { argument in
            let name = URL(fileURLWithPath: argument).lastPathComponent
            return interpreters.contains(name.lowercased()) || name.lowercased().hasPrefix("python") || argument.hasPrefix("-")
        }
        guard let first = rest.first else { return nil }
        rest = rest.dropFirst()
        var words = [program(first).replacingOccurrences(of: #"@[^/@]+$"#, with: "", options: .regularExpression)]
        for argument in rest.prefix(2) {
            guard !argument.hasPrefix("-"), !argument.contains("/"), argument.count <= 24 else { break }
            words.append(argument)
        }
        return words.joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    /// The package name for scripts inside node_modules, otherwise the file name without its extension.
    private static func program(_ path: String) -> String {
        if path.hasPrefix("@"), path.split(separator: "/").count == 2 { return path }
        if let range = path.range(of: "/node_modules/", options: .backwards) {
            let parts = path[range.upperBound...].split(separator: "/")
            if parts.first == ".bin", parts.count > 1 { return String(parts[1]) }
            if let scope = parts.first, scope.hasPrefix("@"), parts.count > 1 { return "\(scope)/\(parts[1])" }
            if let package = parts.first { return String(package) }
        }
        let name = URL(fileURLWithPath: path).lastPathComponent
        for suffix in [".js", ".mjs", ".cjs", ".ts", ".py", ".rb"] where name.hasSuffix(suffix) {
            return String(name.dropLast(suffix.count))
        }
        return name
    }
}

public extension Workload {
    /// The distinct commands behind a development workload, servers with ports first, such as "next dev, tsc +2".
    func commandSummary(arguments: (ProcessIdentity) -> [String]) -> String? {
        guard kind == .development else { return nil }
        let owners = processes.filter { ProcessClassifier.developerKind($0) != nil }
            .sorted { ($0.ports.isEmpty ? 1 : 0, $1.memory) < ($1.ports.isEmpty ? 1 : 0, $0.memory) }
        var commands: [String] = []
        for owner in owners {
            if let command = CommandSummary.make(arguments(owner.identity)), !commands.contains(command) { commands.append(command) }
        }
        guard let first = commands.first else { return nil }
        let shown = [first] + commands.dropFirst().prefix(1)
        return shown.joined(separator: ", ") + (commands.count > 2 ? " +\(commands.count - 2)" : "")
    }

    /// Ports likely to serve a web page; databases and debuggers are left out.
    var webPorts: [UInt16] { ports.filter { ![5432, 3306, 6379, 27017, 9229, 11434].contains($0) } }
}

/// What launched a separate app session, found by walking its parent processes.
public enum SessionOrigin: Equatable {
    case agent(String, folder: String)
    case tool(String, folder: String)
    case app(String)
    /// Kept open by a detached background tool, such as a browser-automation daemon that outlived its agent.
    case background(String)
    /// The process that opened it has exited, so nothing is using it on purpose anymore.
    case leftover
    case unknown

    /// Sessions nothing is actively driving: their launcher exited or runs detached in the background.
    public var isUnattended: Bool {
        switch self {
        case .leftover, .background: return true
        default: return false
        }
    }

    public var description: String {
        switch self {
        case .agent(let name, let folder), .tool(let name, let folder):
            return folder.isEmpty ? "Opened by \(name)" : "Opened by \(name) · \(folder)"
        case .app(let name): return "Opened by \(name)"
        case .background(let name): return "Kept open in the background by \(name)"
        case .leftover: return "Leftover · the tool that opened it has exited"
        case .unknown: return "Origin unknown"
        }
    }

    public static func find(for process: ProcessRecord, in records: [Int32: ProcessRecord], apps: [Int32: String],
                            arguments: (Int32) -> [String], project: (String) -> String = { $0 }) -> SessionOrigin {
        guard process.parent > 1 else { return process.parent == 1 ? .leftover : .unknown }
        var tool: SessionOrigin?
        var helper: String?
        var parent = process.parent
        var seen: Set<Int32> = [process.identity.pid]
        while parent > 1, let record = records[parent], seen.insert(parent).inserted {
            let folder = folderName(project(record.directory))
            switch ProcessClassifier.developerKind(record) {
            case .agent: return .agent(ProcessClassifier.agentName(record), folder: folder)
            case .development:
                tool = tool ?? .tool(CommandSummary.make(arguments(parent)) ?? record.name, folder: folder)
            default:
                if tool == nil, let app = apps[parent] { return .app(app) }
                helper = helper ?? CommandSummary.make(arguments(parent)) ?? record.name
            }
            parent = record.parent
        }
        if let tool { return tool }
        if parent == 1, let helper { return .background(helper) }
        return .unknown
    }

    private static func folderName(_ path: String) -> String {
        path.hasPrefix("/") && path != "/" ? URL(fileURLWithPath: path).lastPathComponent : ""
    }
}
