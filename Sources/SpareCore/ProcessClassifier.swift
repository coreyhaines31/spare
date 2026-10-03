import Foundation

public enum ProcessClassifier {
    public static func developerKind(_ process: ProcessRecord) -> WorkloadKind? {
        let executable = URL(fileURLWithPath: process.path).lastPathComponent.lowercased()
        let name = process.name.lowercased()
        let path = process.path.lowercased()
        if ["claude", "codex", "aider", "ollama", "opencode"].contains(executable) ||
            path.contains("/claude/") || path.contains("/codex/") {
            return .agent
        }
        if ["node", "bun", "deno", "ruby", "php", "java", "uvicorn", "puma"].contains(executable) ||
            executable.hasPrefix("python") || name.hasPrefix("next-server") {
            return .development
        }
        return nil
    }

    public static func agentName(_ process: ProcessRecord) -> String {
        let path = process.path.lowercased()
        for (match, name) in [("claude", "Claude"), ("codex", "Codex"), ("ollama", "Ollama"),
                              ("aider", "Aider"), ("opencode", "OpenCode")] where path.contains(match) {
            return name
        }
        return "AI agent"
    }

    public static func appExplanation(_ name: String) -> (String, String) {
        let lower = name.lowercased()
        if ["chrome", "safari", "firefox", "arc", "brave", "edge"].contains(where: lower.contains) {
            return ("Your browser and its background helpers. Tabs, extensions, and video can all contribute to this total.",
                    "Quitting closes this browser's windows and interrupts downloads. Save anything unfinished first. Spare cannot identify individual tabs yet.")
        }
        if lower.contains("docker") {
            return ("Docker runs a small virtual machine for your containers. Its helpers are included here when ownership is visible.",
                    "Quitting Docker can stop local databases and services used by your projects. Check your containers first.")
        }
        if lower.contains("slack") || lower.contains("discord") {
            return ("Your messaging app, including helpers that display conversations and handle calls.",
                    "Quitting ends active calls and stops desktop notifications until you reopen the app.")
        }
        if lower.contains("notion") {
            return ("Your Notion workspace and the helpers that display pages and keep them up to date.",
                    "Let changes finish syncing before quitting. Your workspace will close until you reopen Notion.")
        }
        if ["clinch", "terminal", "ghostty", "iterm", "warp", "solo", "cursor", "code"].contains(where: lower.contains) {
            return ("Your editor or terminal. Recognized development tools are shown separately when Spare can identify them.",
                    "Quitting may interrupt terminal sessions, running agents, and unsaved work. Review its windows first.")
        }
        return ("This app and the background helpers Spare could associate with it.",
                "Spare will ask the app to quit normally. Save your work first; the app may ask you to save or refuse to close.")
    }
}

public final class ProjectResolver {
    private var cache: [String: String] = [:]
    public init() {}
    public func project(for directory: String) -> String {
        guard directory.hasPrefix("/"), directory != "/" else { return "" }
        if let cached = cache[directory] { return cached }
        var url = URL(fileURLWithPath: directory)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for _ in 0..<8 {
            if url.path == home || url.path == "/" { break }
            let markers = [".git", "package.json", "Gemfile", "pyproject.toml", "Cargo.toml", "go.mod", "Package.swift"]
            if markers.contains(where: { FileManager.default.fileExists(atPath: url.appendingPathComponent($0).path) }) {
                cache[directory] = url.path
                return url.path
            }
            url.deleteLastPathComponent()
        }
        cache[directory] = directory
        return directory
    }
}
