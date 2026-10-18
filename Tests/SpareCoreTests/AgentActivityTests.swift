import XCTest
@testable import SpareCore

final class AgentActivityTests: XCTestCase {
    private let started: UInt64 = 1_000_000_000_000_000 // Process start, in microseconds.
    private var startDate: Date { Date(timeIntervalSince1970: Double(started) / 1_000_000) }

    private func claude(pid: Int32 = 10, cpu: Double = 0) -> ProcessRecord {
        ProcessRecord(pid: pid, started: started, name: "claude", path: "/Users/me/.local/bin/claude", cpu: cpu)
    }

    private func codex(cpu: Double) -> ProcessRecord {
        ProcessRecord(pid: 20, started: started, name: "codex", path: "/opt/homebrew/bin/codex", cpu: cpu)
    }

    func testReadsClaudeCodeStatus() throws {
        let busy = try XCTUnwrap(ClaudeSessionStatus.parse(Data(#"{"pid":17340,"startedAt":1792356767147,"status":"busy"}"#.utf8)))
        XCTAssertEqual(busy.0, 17340)
        XCTAssertTrue(busy.1.busy)
        XCTAssertEqual(busy.1.started.timeIntervalSince1970, 1_792_356_767.147, accuracy: 0.001)
        XCTAssertEqual(ClaudeSessionStatus.parse(Data(#"{"pid":1,"startedAt":1,"status":"idle"}"#.utf8))?.1.busy, false)
        // Unknown or missing statuses aren't guessed at.
        XCTAssertNil(ClaudeSessionStatus.parse(Data(#"{"pid":1,"startedAt":1,"status":"compacting"}"#.utf8)))
        XCTAssertNil(ClaudeSessionStatus.parse(Data(#"{"pid":1,"status":"busy"}"#.utf8)))
        XCTAssertNil(ClaudeSessionStatus.parse(Data("not json".utf8)))
    }

    func testClaudeCodeReportsOutrankCPU() {
        let tracker = AgentActivityTracker(cores: 10)
        let working = tracker.record([claude()], ready: true,
                                     claude: [10: .init(busy: true, started: startDate.addingTimeInterval(60))], now: 0)
        XCTAssertEqual(working[claude().identity], .working)
        let waiting = tracker.record([claude(cpu: 5)], ready: true,
                                     claude: [10: .init(busy: false, started: startDate.addingTimeInterval(60))], now: 3)
        XCTAssertEqual(waiting[claude().identity], .waiting)
    }

    func testIgnoresAStatusFileFromAnEarlierProcessWithTheSamePID() {
        let tracker = AgentActivityTracker(cores: 10)
        let activities = tracker.record([claude()], ready: true,
                                        claude: [10: .init(busy: true, started: startDate.addingTimeInterval(-3600))], now: 0)
        XCTAssertEqual(activities[claude().identity], .quiet)
    }

    func testEstimatesFromRecentCPUForOtherAgents() {
        let tracker = AgentActivityTracker(cores: 10)
        // 0.5% of a 10-core Mac is 5% of one core.
        XCTAssertEqual(tracker.record([codex(cpu: 0.5)], ready: true, claude: [:], now: 0)[codex(cpu: 0).identity], .active)
        XCTAssertEqual(tracker.record([codex(cpu: 0)], ready: true, claude: [:], now: 9)[codex(cpu: 0).identity], .active)
        XCTAssertEqual(tracker.record([codex(cpu: 0)], ready: true, claude: [:], now: 12)[codex(cpu: 0).identity], .quiet)
        XCTAssertEqual(tracker.record([codex(cpu: 0.1)], ready: true, claude: [:], now: 15)[codex(cpu: 0).identity], .quiet)
    }

    func testWaitsForAMeasuredReadingBeforeCallingAnAgentQuiet() {
        let tracker = AgentActivityTracker(cores: 10)
        XCTAssertNil(tracker.record([codex(cpu: 0)], ready: false, claude: [:], now: 0)[codex(cpu: 0).identity])
    }

    func testOnlyTracksAgents() {
        let node = ProcessRecord(pid: 30, name: "node", path: "/opt/homebrew/bin/node", cpu: 50)
        XCTAssertTrue(AgentActivityTracker(cores: 10).record([node], ready: true, claude: [:], now: 0).isEmpty)
    }

    func testCombinesASession() {
        XCTAssertEqual(AgentActivity.combine([.quiet, .working, .active]), .working)
        // Claude Code says it's waiting, even though a helper used some CPU.
        XCTAssertEqual(AgentActivity.combine([.active, .waiting]), .waiting)
        XCTAssertEqual(AgentActivity.combine([.quiet, .active]), .active)
        XCTAssertEqual(AgentActivity.combine([.quiet]), .quiet)
        XCTAssertNil(AgentActivity.combine([]))
    }

    func testWarnsOnlyWhenSomethingLooksMidTask() {
        XCTAssertNotNil(AgentActivity.working.stopWarning(agent: "Claude"))
        XCTAssertNotNil(AgentActivity.active.stopWarning(agent: "Codex"))
        XCTAssertNil(AgentActivity.waiting.stopWarning(agent: "Claude"))
        XCTAssertNil(AgentActivity.quiet.stopWarning(agent: "Codex"))
    }
}
