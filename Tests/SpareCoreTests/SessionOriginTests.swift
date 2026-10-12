import XCTest
@testable import SpareCore

final class SessionOriginTests: XCTestCase {
    func testSummarizesCommands() {
        XCTAssertEqual(CommandSummary.make(["/usr/local/bin/node", "/work/site/node_modules/.bin/next", "dev"]), "next dev")
        XCTAssertEqual(CommandSummary.make(["node", "/work/site/node_modules/next/dist/bin/next", "dev", "--port", "3000"]), "next dev")
        XCTAssertEqual(CommandSummary.make(["node", "/usr/lib/node_modules/@playwright/test/cli.js", "test"]), "@playwright/test test")
        XCTAssertEqual(CommandSummary.make(["/opt/homebrew/bin/python3.12", "-m", "uvicorn", "app:main"]), "uvicorn app:main")
        XCTAssertEqual(CommandSummary.make(["ruby", "/work/api/bin/rails", "server"]), "rails server")
        XCTAssertEqual(CommandSummary.make(["/Library/Frameworks/Python.framework/Versions/3.12/Resources/Python.app/Contents/MacOS/Python", "-m", "http.server", "8765"]), "http.server 8765")
        XCTAssertEqual(CommandSummary.make(["npm exec clipatra@latest serve"]), "clipatra serve")
        XCTAssertEqual(CommandSummary.make(["npm exec clipatra@latest serve", "--port", "1"]), "clipatra serve")
        XCTAssertEqual(CommandSummary.make(["npm exec slack-mcp-server@latest --transport stdio"]), "slack-mcp-server")
        XCTAssertEqual(CommandSummary.make(["npx", "@modelcontextprotocol/server-github@1.2.0"]), "@modelcontextprotocol/server-github")
        XCTAssertNil(CommandSummary.make([]))
    }

    func testFindsAgentAboveTheTool() {
        let records: [Int32: ProcessRecord] = [
            20: ProcessRecord(pid: 20, parent: 10, name: "node", path: "/bin/node", directory: "/work/site"),
            10: ProcessRecord(pid: 10, parent: 1, name: "claude", path: "/bin/claude", directory: "/work/site")
        ]
        let session = ProcessRecord(pid: 30, parent: 20, name: "Chrome", path: "/Apps/Chrome")
        XCTAssertEqual(SessionOrigin.find(for: session, in: records, apps: [:], arguments: { _ in [] }), .agent("Claude", folder: "site"))
    }

    func testFallsBackToToolOrApp() {
        let tool: [Int32: ProcessRecord] = [20: ProcessRecord(pid: 20, parent: 1, name: "node", path: "/bin/node", directory: "/work/site")]
        let session = ProcessRecord(pid: 30, parent: 20, name: "Chrome", path: "/Apps/Chrome")
        XCTAssertEqual(SessionOrigin.find(for: session, in: tool, apps: [:],
                                          arguments: { _ in ["node", "/work/site/node_modules/agent-browser/dist/daemon.js"] }),
                       .tool("agent-browser", folder: "site"))
        let app: [Int32: ProcessRecord] = [40: ProcessRecord(pid: 40, parent: 1, name: "Cursor", path: "/Apps/Cursor")]
        let opened = ProcessRecord(pid: 31, parent: 40, name: "Chrome", path: "/Apps/Chrome")
        XCTAssertEqual(SessionOrigin.find(for: opened, in: app, apps: [40: "Cursor"], arguments: { _ in [] }), .app("Cursor"))
    }

    func testDetachedDaemonKeepsSessionInBackground() {
        let daemonPath = "/Users/me/.nvm/lib/node_modules/agent-browser/bin/agent-browser-darwin-arm64"
        let records: [Int32: ProcessRecord] = [20: ProcessRecord(pid: 20, parent: 1, name: "agent-browser-darwin-arm64", path: daemonPath)]
        let session = ProcessRecord(pid: 30, parent: 20, name: "Chrome", path: "/Apps/Chrome")
        let origin = SessionOrigin.find(for: session, in: records, apps: [:], arguments: { _ in [daemonPath] })
        XCTAssertEqual(origin, .background("agent-browser"))
        XCTAssertTrue(origin.isUnattended)
        XCTAssertFalse(SessionOrigin.agent("Claude", folder: "x").isUnattended)
    }

    func testSessionWhoseLauncherExitedIsLeftover() {
        let session = ProcessRecord(pid: 30, parent: 1, name: "Chrome", path: "/Apps/Chrome")
        XCTAssertEqual(SessionOrigin.find(for: session, in: [:], apps: [:], arguments: { _ in [] }), .leftover)
    }

    func testDevelopmentWorkloadCommandAndWebPorts() {
        let server = ProcessRecord(pid: 50, name: "node", path: "/bin/node", directory: "/work/site", ports: [3000, 9229])
        let workloads = WorkloadGrouper.group([server], apps: [])
        let site = workloads.first { $0.kind == .development }
        XCTAssertEqual(site?.commandSummary(arguments: { _ in ["node", "/work/site/node_modules/next/dist/bin/next", "dev"] }), "next dev")
        XCTAssertEqual(site?.webPorts, [3000])
        let tools = WorkloadGrouper.group([
            ProcessRecord(pid: 60, name: "node", path: "/bin/node", directory: "/work/app", memory: 10),
            ProcessRecord(pid: 61, name: "node", path: "/bin/node", directory: "/work/app", memory: 30),
            ProcessRecord(pid: 62, name: "node", path: "/bin/node", directory: "/work/app", memory: 20, ports: [5173]),
            ProcessRecord(pid: 63, name: "node", path: "/bin/node", directory: "/work/app", memory: 5)
        ], apps: []).first
        let names: [Int32: String] = [60: "a-mcp", 61: "b-mcp", 62: "vite", 63: "a-mcp"]
        XCTAssertEqual(tools?.commandSummary(arguments: { ["node", "/x/node_modules/\(names[$0.pid]!)/cli.js"] }), "vite, b-mcp +1")
    }
}
