import XCTest
import CSpare
@testable import SpareCore

final class MonitorTests: XCTestCase {
    func testHelpersBelongToAppAndDeveloperToolsStaySeparate() {
        let app = AppRecord(pid: 10, name: "Editor", path: "/Applications/Editor.app", canQuit: true)
        let records = [
            ProcessRecord(pid: 10, name: "Editor", path: "/Applications/Editor.app/Contents/MacOS/Editor", memory: 100),
            ProcessRecord(pid: 11, parent: 10, name: "Helper", path: "/Applications/Editor.app/Contents/Helpers/Helper", memory: 200),
            ProcessRecord(pid: 12, parent: 10, name: "node", path: "/opt/homebrew/bin/node", directory: "/work/website", memory: 400),
            ProcessRecord(pid: 13, parent: 12, name: "worker", path: "/usr/bin/worker", memory: 50)
        ]
        let groups = WorkloadGrouper.group(records, apps: [app])
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.first(where: { $0.kind == .application })?.memory, 300)
        XCTAssertEqual(groups.first(where: { $0.kind == .development })?.memory, 450)
        XCTAssertEqual(groups.flatMap(\.processes).count, records.count)
    }

    func testAgentsAndUnidentifiedTasksHaveDistinctSafetyRules() {
        let records = [
            ProcessRecord(pid: 20, name: "codex", path: "/usr/local/bin/codex", directory: "/work/api"),
            ProcessRecord(pid: 21, name: "mystery", path: "/usr/bin/mystery")
        ]
        let groups = WorkloadGrouper.group(records, apps: [])
        XCTAssertEqual(groups.first(where: { $0.kind == .agent })?.name, "Codex · api")
        XCTAssertEqual(groups.first(where: { $0.kind == .background })?.canStop, false)
    }

    func testHighMemoryUseAloneDoesNotRaiseAlarm() {
        let health = Health(samples: [SystemSample(memory: 99, physical: 100, swap: 50, pressure: .normal)], ready: true)
        XCTAssertEqual(health.level, 0)
        XCTAssertEqual(Health(samples: [SystemSample(pressure: .critical)], ready: true).level, 2)
    }

    func testCPUAlertRequiresSustainedReadings() {
        let now = Date()
        let sustained = (0..<7).map { SystemSample(date: now.addingTimeInterval(Double($0) * 3), cpu: 95, pressure: .normal) }
        XCTAssertEqual(Health(samples: Array(sustained.prefix(6)), ready: true).level, 0)
        XCTAssertEqual(Health(samples: sustained, ready: true).level, 1)
        var interrupted = sustained
        interrupted[4].cpu = 10
        XCTAssertEqual(Health(samples: interrupted, ready: true).level, 0)
        XCTAssertEqual(Health(samples: sustained, ready: false).level, 0)
    }

    func testNativeSamplerReturnsCurrentProcessAndSystemMemory() throws {
        let snapshot = try XCTUnwrap(Sampler().sample())
        XCTAssertGreaterThan(snapshot.system.physical, 0)
        XCTAssertTrue(snapshot.processes.contains { $0.identity.pid == getpid() })
        XCTAssertFalse(snapshot.ready)
        XCTAssertGreaterThanOrEqual(snapshot.system.cpu, 0)
        XCTAssertLessThanOrEqual(snapshot.system.cpu, 100)
    }

    func testStopRevalidatesIdentityAndOnlyStopsFixture() throws {
        let fixture = Process()
        fixture.executableURL = URL(fileURLWithPath: "/bin/sleep")
        fixture.arguments = ["30"]
        try fixture.run()
        defer { if fixture.isRunning { fixture.terminate() }; fixture.waitUntilExit() }
        var record = SpareProcess()
        XCTAssertTrue(spare_process(fixture.processIdentifier, &record, true))
        XCTAssertNotEqual(spare_stop(record.pid, record.started + 1), 0)
        XCTAssertTrue(fixture.isRunning)
        XCTAssertNotEqual(spare_stop(getpid(), 0), 0)
        XCTAssertEqual(spare_stop(record.pid, record.started), 0)
        fixture.waitUntilExit()
        XCTAssertEqual(fixture.terminationReason, .uncaughtSignal)
    }
}
