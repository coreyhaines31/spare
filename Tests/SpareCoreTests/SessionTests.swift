import XCTest
@testable import SpareCore

final class SessionTests: XCTestCase {
    func testSessionsSeparateIndependentAgentsAndKeepTheirChildren() throws {
        let processes = [
            ProcessRecord(pid: 1, started: 10, name: "claude", path: "/bin/claude", directory: "/work/api", memory: 100),
            ProcessRecord(pid: 2, started: 20, parent: 1, name: "node", path: "/bin/node", directory: "/work/api", memory: 50),
            ProcessRecord(pid: 3, started: 30, parent: 99, name: "claude", path: "/bin/claude", directory: "/work/api", memory: 200)
        ]
        let group = try XCTUnwrap(WorkloadGrouper.group(processes, apps: []).first)
        let sessions = group.sessions
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(Set(sessions.map(\.memory)), [150, 200])
        XCTAssertEqual(Set(sessions.flatMap(\.processes).map(\.identity)), Set(processes.map(\.identity)))
        XCTAssertEqual(sessions[0].current(in: [group])?.id, sessions[0].id)
        XCTAssertNil(sessions[0].current(in: []))
    }

    func testStopFollowUpDistinguishesWaitingTimeoutAndPIDReuse() {
        let original = ProcessIdentity(pid: 123, started: 1)
        let followUp = StopFollowUp(identities: [original], now: 100)
        XCTAssertEqual(followUp.result(visible: [original], now: 110), .waiting)
        XCTAssertEqual(followUp.result(visible: [original], now: 116), .stillRunning(1))
        XCTAssertEqual(followUp.result(visible: [ProcessIdentity(pid: 123, started: 2)], now: 110), .noLongerVisible)
    }
}
