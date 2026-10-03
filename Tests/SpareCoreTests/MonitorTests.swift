import XCTest
import CSpare
import Darwin
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
    func testListeningPortDetection() throws {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        XCTAssertEqual(bound, 0)
        XCTAssertEqual(listen(descriptor, 1), 0)
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let result = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) }
        }
        XCTAssertEqual(result, 0)
        var ports = [UInt16](repeating: 0, count: 64)
        let count = spare_ports(getpid(), &ports, 64)
        XCTAssertTrue(ports.prefix(Int(count)).contains(UInt16(bigEndian: address.sin_port)))
    }

    func testProjectResolverFindsParentManifest() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let child = root.appendingPathComponent("src/server")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("{}".utf8).write(to: root.appendingPathComponent("package.json"))
        XCTAssertEqual(ProjectResolver().project(for: child.path), root.path)
        XCTAssertEqual(ProjectResolver().project(for: ""), "")
    }

    func testAgentOwnsItsRuntimeChildrenButNotIndependentServer() {
        let records = [
            ProcessRecord(pid: 30, name: "claude", path: "/usr/local/bin/claude", directory: "/work/api", memory: 100),
            ProcessRecord(pid: 31, parent: 30, name: "node", path: "/usr/local/bin/node", directory: "/work/api", memory: 200),
            ProcessRecord(pid: 32, parent: 31, name: "worker", path: "/usr/bin/worker", memory: 50),
            ProcessRecord(pid: 33, name: "node", path: "/usr/local/bin/node", directory: "/work/api", memory: 400)
        ]
        let groups = WorkloadGrouper.group(records, apps: [])
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.first(where: { $0.kind == .agent })?.memory, 350)
        XCTAssertEqual(groups.first(where: { $0.kind == .development })?.memory, 400)
    }

    func testSuggestionUsesRelevantResourceAndRespectsProtectedTasks() throws {
        let records = [
            ProcessRecord(pid: 40, name: "node", path: "/usr/local/bin/node", directory: "/work/memory", memory: 900, cpu: 2),
            ProcessRecord(pid: 41, name: "node", path: "/usr/local/bin/node", directory: "/work/cpu", memory: 100, cpu: 40, ports: [3456]),
            ProcessRecord(pid: 42, name: "unknown", path: "/usr/bin/unknown", memory: 9999, cpu: 50)
        ]
        let groups = WorkloadGrouper.group(records, apps: [])
        XCTAssertNil(ReviewSuggestion.make(workloads: groups, samples: [SystemSample(pressure: .normal)], ready: true))
        let memory = ReviewSuggestion.make(workloads: groups, samples: [SystemSample(pressure: .warning)], ready: true)
        XCTAssertEqual(memory?.workload.name, "memory")
        let now = Date()
        let highCPU = (0..<7).map { SystemSample(date: now.addingTimeInterval(Double($0) * 3), cpu: 95, pressure: .normal) }
        XCTAssertEqual(ReviewSuggestion.make(workloads: groups, samples: highCPU, ready: true)?.workload.name, "cpu")
        XCTAssertNil(ReviewSuggestion.make(workloads: groups, samples: highCPU, ready: false))
        let server = try XCTUnwrap(groups.first(where: { $0.name == "cpu" }))
        XCTAssertTrue(server.matches("CPU 3456"))
        XCTAssertFalse(server.matches("CPU 9999"))
        XCTAssertTrue(WorkloadFilter.projects.includes(server))
        XCTAssertFalse(WorkloadFilter.agents.includes(server))
    }

}
