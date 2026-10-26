import XCTest
@testable import SpareCore

final class StrayProcessTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private func started(hoursAgo hours: Double) -> UInt64 { UInt64((now.timeIntervalSince1970 - hours * 3600) * 1_000_000) }
    private func table(_ records: [ProcessRecord]) -> [Int32: ProcessRecord] {
        Dictionary(uniqueKeysWithValues: records.map { ($0.identity.pid, $0) })
    }

    func testClassifiesKnownCulprits() {
        let none: () -> [String] = { [] }
        XCTAssertEqual(StrayProcesses.classify(ProcessRecord(pid: 2, name: "cloudflared", path: "/opt/homebrew/bin/cloudflared"), arguments: none)?.kind, .tunnel)
        XCTAssertEqual(StrayProcesses.classify(ProcessRecord(pid: 2, name: "x", path: "/u/.agent-browser/browsers/chrome-1/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing"), arguments: none)?.kind, .headlessBrowser)
        XCTAssertNil(StrayProcesses.classify(ProcessRecord(pid: 2, name: "x", path: "/u/Google Chrome for Testing.app/Contents/Frameworks/Helpers/chrome_crashpad_handler"), arguments: none))
        XCTAssertEqual(StrayProcesses.classify(ProcessRecord(pid: 2, name: "x", path: "/u/.npm/_npx/1/node_modules/slack-mcp-server-darwin-arm64/bin/slack-mcp-server-darwin-arm64"), arguments: none)?.name, "slack-mcp-server")
        XCTAssertNil(StrayProcesses.classify(ProcessRecord(pid: 2, name: "Cursor Helper: mcp-process", path: "/Applications/Cursor.app/Contents/Frameworks/Cursor Helper.app/Contents/MacOS/Cursor Helper"), arguments: none))
        XCTAssertEqual(StrayProcesses.classify(ProcessRecord(pid: 2, name: "node", path: "/bin/node"), arguments: { ["npm exec slack-mcp-server@latest --transport stdio"] })?.kind, .mcpServer)
        XCTAssertEqual(StrayProcesses.classify(ProcessRecord(pid: 2, name: "python3", path: "/usr/bin/python3"), arguments: { ["python3", "-m", "http.server", "8000"] })?.kind, .fileServer)
        XCTAssertEqual(StrayProcesses.classify(ProcessRecord(pid: 2, name: "node", path: "/bin/node"), arguments: { ["node", "/w/node_modules/.bin/vite"] })?.name, "vite")
        XCTAssertEqual(StrayProcesses.classify(ProcessRecord(pid: 2, name: "next-server (v16.2.6)", path: "/bin/node"), arguments: none)?.kind, .devServer)
        XCTAssertNil(StrayProcesses.classify(ProcessRecord(pid: 2, name: "node", path: "/bin/node"), arguments: { ["node", "/w/node_modules/.bin/tsc", "--watch"] }))
        XCTAssertFalse(StrayProcesses.isMCP("npm"))
        XCTAssertFalse(StrayProcesses.isMCP("mcpherson"))
        XCTAssertTrue(StrayProcesses.isMCP("@modelcontextprotocol/server-github"))
        XCTAssertTrue(StrayProcesses.isMCP("mcp-remote"))
    }

    func testOrphanedMCPServerIsAStrayWithItsWholeTree() {
        let records = table([
            ProcessRecord(pid: 10, started: started(hoursAgo: 3), parent: 1, name: "node", path: "/bin/node", memory: 40),
            ProcessRecord(pid: 11, started: started(hoursAgo: 3), parent: 10, name: "sh", path: "/bin/sh", memory: 1),
            ProcessRecord(pid: 12, started: started(hoursAgo: 3), parent: 11, name: "slack-mcp-server-darwin-arm64",
                          path: "/Users/me/.Trash/node_modules/slack-mcp-server-darwin-arm64/bin/slack-mcp-server-darwin-arm64", memory: 13)
        ])
        let strays = StrayProcesses.find(records: records, arguments: { $0.pid == 10 ? ["npm exec slack-mcp-server@latest"] : [] }, now: now)
        XCTAssertEqual(strays.count, 1)
        XCTAssertEqual(strays[0].root.identity.pid, 10)
        XCTAssertEqual(strays[0].tree.map(\.identity.pid), [12, 11, 10])
        XCTAssertEqual(strays[0].memory, 54)
        XCTAssertFalse(strays[0].isHeld)
        XCTAssertEqual(strays[0].reason, "Started 3h ago · the tool that started it has exited · runs from the Trash, which can keep it from emptying")
    }

    func testLiveAgentHoldsItsServers() {
        let records = table([
            ProcessRecord(pid: 5, started: started(hoursAgo: 90), parent: 1, name: "claude", path: "/u/.local/bin/claude", directory: "/w/site"),
            ProcessRecord(pid: 12, started: started(hoursAgo: 90), parent: 5, name: "mcp-server-darwin-arm64", path: "/u/.pencil/mcp/out/mcp-server-darwin-arm64")
        ])
        let strays = StrayProcesses.find(records: records, arguments: { _ in [] }, now: now)
        XCTAssertEqual(strays.map(\.heldBy), ["Claude · site"])
    }

    func testDaemonAndItsBrowserAreOneStrayOnceOldEnough() {
        let records = { (hours: Double) in self.table([
            ProcessRecord(pid: 20, started: self.started(hoursAgo: hours), parent: 1, name: "agent-browser-darwin-arm64",
                          path: "/u/lib/node_modules/agent-browser/bin/agent-browser-darwin-arm64", memory: 5),
            ProcessRecord(pid: 21, started: self.started(hoursAgo: hours), parent: 20, name: "Google Chrome for Testing",
                          path: "/u/.agent-browser/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing", memory: 100),
            ProcessRecord(pid: 22, started: self.started(hoursAgo: hours), parent: 21, name: "Google Chrome for Testing Helper (Renderer)",
                          path: "/u/.agent-browser/Google Chrome for Testing.app/Contents/Frameworks/Helper (Renderer)", memory: 50)
        ]) }
        XCTAssertTrue(StrayProcesses.find(records: records(0.1), arguments: { _ in [] }, now: now).isEmpty)
        let strays = StrayProcesses.find(records: records(2), arguments: { _ in [] }, now: now)
        XCTAssertEqual(strays.map(\.name), ["agent-browser"])
        XCTAssertEqual(strays[0].tree.first?.identity.pid, 22)
        XCTAssertEqual(strays[0].memory, 155)
    }

    func testDevServersCountAfterADayEvenWithATerminal() {
        let records = { (hours: Double) in self.table([
            ProcessRecord(pid: 30, started: self.started(hoursAgo: hours), parent: 2, name: "zsh", path: "/bin/zsh"),
            ProcessRecord(pid: 31, started: self.started(hoursAgo: hours), parent: 30, name: "node", path: "/bin/node", directory: "/w/site")
        ]) }
        let arguments: (ProcessIdentity) -> [String] = { $0.pid == 31 ? ["node", "/w/site/node_modules/.bin/next", "dev"] : [] }
        XCTAssertTrue(StrayProcesses.find(records: records(5), arguments: arguments, now: now).isEmpty)
        let strays = StrayProcesses.find(records: records(30), arguments: arguments, now: now)
        XCTAssertEqual(strays.map(\.reason), ["Running for 30h"])
        XCTAssertEqual(strays.map(\.name), ["next dev · site"])
    }

    func testTreeWithALiveAgentInsideIsNeverAStray() {
        let records = table([
            ProcessRecord(pid: 50, started: started(hoursAgo: 2), parent: 1, name: "python3", path: "/usr/bin/python3"),
            ProcessRecord(pid: 51, started: started(hoursAgo: 1), parent: 50, name: "claude", path: "/u/.local/bin/claude")
        ])
        XCTAssertTrue(StrayProcesses.find(records: records, arguments: { $0.pid == 50 ? ["python3", "-m", "http.server"] : [] }, now: now).isEmpty)
    }

    func testPublicTunnelsRankFirst() {
        let records = table([
            ProcessRecord(pid: 40, started: started(hoursAgo: 1), parent: 1, name: "node", path: "/bin/node", memory: 900),
            ProcessRecord(pid: 41, started: started(hoursAgo: 1), parent: 1, name: "ngrok", path: "/opt/homebrew/bin/ngrok", memory: 10)
        ])
        let strays = StrayProcesses.find(records: records, arguments: { $0.pid == 40 ? ["npx", "mcp-remote"] : [] }, now: now)
        XCTAssertEqual(strays.map(\.kind), [.tunnel, .mcpServer])
        XCTAssertTrue(strays[0].reason.hasPrefix("Reachable from the internet"))
    }
}
