import XCTest
@testable import SpareCore

final class CommandLineTests: XCTestCase {
    private let workloads = WorkloadGrouper.group([
        ProcessRecord(pid: 10, name: "Slack", path: "/Applications/Slack.app/Contents/MacOS/Slack", memory: 900),
        ProcessRecord(pid: 20, name: "Google Chrome", path: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", memory: 4000),
        ProcessRecord(pid: 21, parent: 20, name: "Google Chrome Helper", path: "/Applications/Google Chrome.app/Contents/Frameworks/Helper", memory: 500),
        ProcessRecord(pid: 30, name: "Google Chrome for Testing", path: "/Users/me/.cache/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing", memory: 300),
        ProcessRecord(pid: 40, name: "node", path: "/opt/homebrew/bin/node", directory: "/work/website", memory: 700, ports: [3000])
    ], apps: [
        AppRecord(pid: 10, name: "Slack", path: "/Applications/Slack.app", canQuit: true),
        AppRecord(pid: 20, name: "Google Chrome", path: "/Applications/Google Chrome.app", canQuit: true),
        AppRecord(pid: 30, name: "Google Chrome for Testing", path: "/Users/me/.cache/Google Chrome for Testing.app", canQuit: true)
    ])

    private func name(_ result: WorkloadLookup.Result) -> String? {
        if case .found(let workload) = result { return workload.name }
        return nil
    }

    func testLooksUpByNameIdProcessAndPrefix() {
        XCTAssertEqual(name(WorkloadLookup.find("slack", in: workloads)), "Slack")
        XCTAssertEqual(name(WorkloadLookup.find("development:/work/website", in: workloads)), "website")
        XCTAssertEqual(name(WorkloadLookup.find("21", in: workloads)), "Google Chrome")
        XCTAssertEqual(name(WorkloadLookup.find("3000", in: workloads)), "website")
        // An exact name wins over a longer name that starts the same way.
        XCTAssertEqual(name(WorkloadLookup.find("Google Chrome", in: workloads)), "Google Chrome")
        XCTAssertEqual(name(WorkloadLookup.find("google chrome for", in: workloads)), "Google Chrome for Testing")
    }

    func testReportsAmbiguousAndMissingNames() {
        guard case .ambiguous(let matches) = WorkloadLookup.find("goo", in: workloads) else { return XCTFail("expected ambiguous") }
        XCTAssertEqual(Set(matches.map(\.name)), ["Google Chrome", "Google Chrome for Testing"])
        guard case .notFound = WorkloadLookup.find("zoom", in: workloads) else { return XCTFail("expected not found") }
        guard case .notFound = WorkloadLookup.find("  ", in: workloads) else { return XCTFail("expected not found") }
    }

    func testSummaryUsesCommandNamesAndRoundsCPU() throws {
        var project = try XCTUnwrap(workloads.first { $0.name == "website" })
        project.processes[0].cpu = 3.14159
        let summary = WorkloadSummary(project, command: "next dev")
        XCTAssertEqual(summary.kind, "project")
        XCTAssertEqual(summary.cpuPercent, 3.1)
        XCTAssertEqual(summary.ports, [3000])
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let json = try XCTUnwrap(String(data: encoder.encode(summary), encoding: .utf8))
        XCTAssertTrue(json.contains("\"memory_bytes\":700"))
        XCTAssertTrue(json.contains("\"can_quit\":true"))
    }

    func testStatusExitCodeFollowsMemoryPressure() {
        XCTAssertEqual(StatusSummary(sample: SystemSample(cpu: 20, pressure: .normal), ready: true).exitCode, 0)
        XCTAssertEqual(StatusSummary(sample: SystemSample(cpu: 20, pressure: .warning), ready: true).exitCode, 2)
        XCTAssertEqual(StatusSummary(sample: SystemSample(cpu: 20, pressure: .critical), ready: true).exitCode, 3)
        XCTAssertEqual(StatusSummary(sample: SystemSample(cpu: 20, pressure: .unknown), ready: true).exitCode, 0)
        XCTAssertEqual(StatusSummary(sample: SystemSample(cpu: 23.96), ready: true).cpuAvailablePercent, 76)
    }

    func testTableAlignsColumnsAndClipsLongCells() {
        let table = TextTable.render([["NAME", "MEMORY", ""], ["Slack", "900 MB", ""], ["Google Chrome for Testing", "1.2 GB", "x"]],
                                     rightAligned: [1], maxWidth: [0: 10])
        XCTAssertEqual(table, """
        NAME        MEMORY
        Slack       900 MB
        Google Ch…  1.2 GB  x
        """)
    }

    func testFindsOnlyUnattendedSessionsWithTheirHelpers() {
        let main = "/Apps/Chrome.app/Contents/MacOS/Chrome"
        let processes = [
            ProcessRecord(pid: 50, name: "Chrome", path: main, memory: 100),
            ProcessRecord(pid: 60, parent: 1, name: "Chrome", path: main, memory: 200),
            ProcessRecord(pid: 61, parent: 60, name: "Chrome Helper", path: "/Apps/Chrome.app/Contents/Frameworks/Helper", memory: 50),
            ProcessRecord(pid: 70, parent: 80, name: "Chrome", path: main, memory: 300),
            ProcessRecord(pid: 80, parent: 1, name: "claude", path: "/bin/claude", directory: "/work/site", memory: 10)
        ]
        let grouped = WorkloadGrouper.group(processes, apps: [AppRecord(pid: 50, name: "Chrome", path: "/Apps/Chrome.app", canQuit: true)])
        let records = Dictionary(uniqueKeysWithValues: processes.map { ($0.identity.pid, $0) })
        let leftovers = Leftovers.find(grouped, records: records, apps: [50: "Chrome"]) { identity in
            identity.pid == 60 || identity.pid == 70 ? [main, "--user-data-dir=/tmp/x"] : []
        }
        XCTAssertEqual(leftovers.map(\.process.identity.pid), [60])
        XCTAssertEqual(leftovers.first?.memory, 250)
        XCTAssertEqual(leftovers.first?.origin, .leftover)
        // Other apps run extra copies of themselves as services; those aren't sessions.
        let service = WorkloadGrouper.group(processes.map { var copy = $0; copy.path = copy.path.replacingOccurrences(of: "Chrome", with: "Docker"); return copy },
                                            apps: [AppRecord(pid: 50, name: "Docker", path: "/Apps/Docker.app", canQuit: true)])
        XCTAssertTrue(Leftovers.find(service, records: records, apps: [50: "Docker"]) { _ in ["--flag"] }.isEmpty)
    }

    func testRequesterNamesTheAgentAndFolder() {
        XCTAssertEqual(SessionOrigin.agent("Claude", folder: "website").requesterName, "Claude in website")
        XCTAssertEqual(SessionOrigin.app("Terminal").requesterName, "Terminal")
        XCTAssertNil(SessionOrigin.leftover.requesterName)
    }

    func testRequestsRoundTripThroughUserInfo() {
        let message = CommandRequest.Message(action: .quit, target: "app:/Applications/Slack.app", requester: "Codex in api")
        XCTAssertEqual(CommandRequest.Message(userInfo: message.userInfo), message)
        let reply = CommandRequest.Reply(id: message.id, outcome: .approved, message: "Quit requested for Slack.",
                                         identities: [ProcessIdentity(pid: 10, started: 123), ProcessIdentity(pid: 11, started: 456)])
        XCTAssertEqual(CommandRequest.Reply(userInfo: reply.userInfo), reply)
        XCTAssertNil(CommandRequest.Message(userInfo: ["id": "x", "action": "format-disk"]))
    }

    func testWatchingSinceTrustsOnlyActivityFromThatRun() {
        let name = "CommandLineTests-\(UUID().uuidString)"
        let store = UserDefaults(suiteName: name)!
        defer { store.removePersistentDomain(forName: name) }
        let launch = Date(timeIntervalSince1970: 1_000_000)
        AppActivityLog(defaults: store, now: launch.addingTimeInterval(-50_000)).recordActivation(appPath: "/Old.app", at: launch.addingTimeInterval(-40_000))
        AppActivityLog(defaults: store, now: launch).recordActivation(appPath: "/New.app", at: launch.addingTimeInterval(1_000))
        let reader = AppActivityLog(defaults: store, now: launch.addingTimeInterval(9_000), watchingSince: launch)
        let now = launch.addingTimeInterval(9_000)
        XCTAssertEqual(reader.idleTime(appPath: "/Old.app", launched: nil, now: now), 9_000)
        XCTAssertEqual(reader.idleTime(appPath: "/New.app", launched: nil, now: now), 8_000)
        XCTAssertEqual(reader.idleTime(appPath: "/Never.app", launched: nil, now: now), 9_000)
    }
}
