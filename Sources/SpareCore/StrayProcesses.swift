import Foundation

/// Something a coding agent or tool started and walked away from, such as a headless browser or an orphaned MCP server.
public struct StrayProcess {
    public enum Kind: String, Codable, CaseIterable {
        case tunnel
        case fileServer = "file-server"
        case headlessBrowser = "headless-browser"
        case mcpServer = "mcp-server"
        case devServer = "dev-server"

        public var label: String {
            switch self {
            case .tunnel: return "Public tunnel"
            case .fileServer: return "File server"
            case .headlessBrowser: return "Headless browser"
            case .mcpServer: return "MCP server"
            case .devServer: return "Dev server"
            }
        }

        public var symbol: String {
            switch self {
            case .tunnel: return "network"
            case .fileServer: return "folder"
            case .headlessBrowser: return "globe"
            case .mcpServer: return "puzzlepiece.extension"
            case .devServer: return "hammer"
            }
        }
    }

    public let kind: Kind
    /// A short name, such as "slack-mcp-server", "agent-browser", or "next dev".
    public let name: String
    public let root: ProcessRecord
    /// The root and everything it started, children before their parents: the order to stop them in.
    public let tree: [ProcessRecord]
    public let reason: String
    /// The live agent session above it, such as "Claude · website". Held processes are left alone.
    public let heldBy: String?
    public var memory: UInt64 { tree.reduce(0) { $0 + $1.memory } }
    public var isHeld: Bool { heldBy != nil }
}

public enum StrayProcesses {
    /// Younger than this, an orphan may still be in use by whatever just started it.
    public static let minimumAge: TimeInterval = 15 * 60
    /// Dev servers count once they've run this long, even when a terminal still owns them.
    public static let devServerAge: TimeInterval = 24 * 3600

    /// Strays and held candidates, tunnels and file servers first since they're reachable from outside, then largest first.
    /// `arguments` reads a process's launch arguments; it's only called for runtimes like node and python.
    public static func find(records: [Int32: ProcessRecord], arguments: (ProcessIdentity) -> [String],
                            project: (String) -> String = { $0 }, now: Date = Date()) -> [StrayProcess] {
        var kinds: [Int32: (kind: StrayProcess.Kind, name: String)] = [:]
        for (pid, record) in records {
            if let match = classify(record, arguments: { arguments(record.identity) }) { kinds[pid] = match }
        }
        let children = Dictionary(grouping: records.values, by: \.parent)
        /// Each root to the live agent holding it, or "" when nothing does.
        var roots: [Int32: String] = [:]
        for pid in kinds.keys {
            var root = pid
            var heldBy: String?
            var seen: Set<Int32> = [pid]
            var parent = records[pid]?.parent ?? 0
            while parent > 1, let record = records[parent], seen.insert(parent).inserted, seen.count < 32 {
                if ProcessClassifier.developerKind(record) == .agent {
                    let folder = folderName(project(record.directory))
                    let agent = ProcessClassifier.agentName(record)
                    heldBy = folder.isEmpty ? agent : "\(agent) · \(folder)"
                    break
                }
                if kinds[parent] != nil { root = parent }
                parent = record.parent
            }
            roots[root] = heldBy ?? ""
        }
        return roots.compactMap { pid, holder -> StrayProcess? in
            guard let root = records[pid], let match = kinds[pid] else { return nil }
            let heldBy = holder.isEmpty ? nil : holder
            let age = max(0, now.timeIntervalSince1970 - Double(root.identity.started) / 1_000_000)
            let orphaned = root.parent == 1
            var parts: [String] = []
            if heldBy == nil {
                if match.kind == .devServer && age >= devServerAge {
                    parts.append("Running for \(duration(age))")
                } else if orphaned && age >= minimumAge {
                    parts.append("Started \(duration(age)) ago · the tool that started it has exited")
                } else {
                    return nil
                }
            } else {
                parts.append("Running for \(duration(age))")
            }
            if match.kind == .tunnel { parts.insert("Reachable from the internet", at: 0) }
            if match.kind == .fileServer { parts.insert("Shares a folder with your network", at: 0) }
            let processes = tree(from: root, children: children)
            if processes.contains(where: { $0.path.contains("/.Trash/") }) { parts.append("runs from the Trash, which can keep it from emptying") }
            let folder = folderName(project(root.directory))
            let name = [.devServer, .fileServer].contains(match.kind) && !folder.isEmpty ? "\(match.name) · \(folder)" : match.name
            return StrayProcess(kind: match.kind, name: name, root: root, tree: processes,
                                reason: parts.joined(separator: " · "), heldBy: heldBy)
        }.sorted { left, right in
            let rank = { (kind: StrayProcess.Kind) in kind == .tunnel ? 0 : kind == .fileServer ? 1 : 2 }
            return (rank(left.kind), right.memory, left.root.identity.pid) < (rank(right.kind), left.memory, right.root.identity.pid)
        }
    }

    static func classify(_ process: ProcessRecord, arguments: () -> [String]) -> (kind: StrayProcess.Kind, name: String)? {
        let executable = URL(fileURLWithPath: process.path).lastPathComponent.lowercased()
        let path = process.path.lowercased()
        if ["cloudflared", "ngrok"].contains(executable) { return (.tunnel, executable) }
        if executable.hasPrefix("agent-browser") { return (.headlessBrowser, "agent-browser") }
        // Crash reporters outlive the browser on their own and are tiny, so they aren't listed.
        if !executable.contains("crashpad") {
            if path.contains("chrome for testing") { return (.headlessBrowser, "Chrome for Testing") }
            if executable.hasPrefix("chrome-headless-shell") || executable.hasPrefix("headless_shell") { return (.headlessBrowser, "headless Chrome") }
        }
        if !path.contains(".app/"), isMCP(executable) { return (.mcpServer, executable.replacingOccurrences(of: "-darwin-arm64", with: "")) }
        let nextServer = process.name.lowercased().hasPrefix("next-server")
        guard nextServer || ProcessClassifier.developerKind(process) == .development else { return nil }
        if nextServer { return (.devServer, "next dev") }
        let arguments = arguments()
        if arguments.contains("http.server") || arguments.contains("SimpleHTTPServer") { return (.fileServer, "python http.server") }
        guard let command = CommandSummary.make(arguments) else { return nil }
        let program = command.split(separator: " ").first.map(String.init) ?? command
        if program == "http-server" { return (.fileServer, "http-server") }
        if isMCP(program) { return (.mcpServer, program) }
        if command.hasPrefix("next dev") || program == "vite" || command.hasPrefix("webpack serve") || program == "webpack-dev-server" {
            return (.devServer, command.hasPrefix("next dev") ? "next dev" : program == "vite" ? "vite" : "webpack serve")
        }
        return nil
    }

    /// Names like "slack-mcp-server", "screenpipe-mcp", "mcp-remote", or "@modelcontextprotocol/server-github".
    static func isMCP(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.contains("modelcontextprotocol") ||
            lower.range(of: #"(^|[-_/@])mcp($|[-_])"#, options: .regularExpression) != nil
    }

    private static func tree(from root: ProcessRecord, children: [Int32: [ProcessRecord]]) -> [ProcessRecord] {
        var ordered = [root]
        var seen: Set<Int32> = [root.identity.pid]
        var index = 0
        while index < ordered.count {
            for child in children[ordered[index].identity.pid] ?? [] where seen.insert(child.identity.pid).inserted {
                ordered.append(child)
            }
            index += 1
        }
        return ordered.reversed()
    }

    public static func duration(_ time: TimeInterval) -> String {
        let hours = Int(time / 3600)
        if hours >= 48 { return "\(hours / 24) days" }
        if hours >= 1 { return "\(hours)h" }
        return "\(max(1, Int(time / 60)))m"
    }

    private static func folderName(_ path: String) -> String {
        path.hasPrefix("/") && path != "/" ? URL(fileURLWithPath: path).lastPathComponent : ""
    }
}
