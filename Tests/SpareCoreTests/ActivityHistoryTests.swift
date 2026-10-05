import XCTest
@testable import SpareCore

final class ActivityHistoryTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 10000)
    private func record(_ history: ActivityHistory, _ seconds: Double, _ pressure: MemoryPressure, ready: Bool = true) {
        history.record(samples: [SystemSample(date: start.addingTimeInterval(seconds), pressure: pressure)], workloads: [], ready: ready)
    }

    func testEventsAreDeduplicatedAndRecoveryNeedsThirtySeconds() {
        let history = ActivityHistory()
        record(history, 0, .warning)
        record(history, 3, .warning)
        XCTAssertEqual(history.events.count, 1)
        for second in stride(from: 6, through: 33, by: 3) { record(history, Double(second), .normal) }
        XCTAssertEqual(history.events.count, 1)
        record(history, 36, .normal)
        XCTAssertEqual(history.events.first?.title, "Pressure eased")
    }

    func testSleepGapAndUnknownPressureDoNotClaimRecovery() {
        let history = ActivityHistory()
        record(history, 0, .critical)
        record(history, 3, .unknown)
        XCTAssertEqual(history.events.first?.title, "Memory pressure unavailable")
        record(history, 60, .normal)
        XCTAssertTrue(history.events.contains { $0.title == "Monitoring gap" })
        XCTAssertFalse(history.events.contains { $0.title == "Pressure eased" })
        record(history, 63, .normal, ready: false)
        record(history, 66, .normal, ready: false)
        XCTAssertEqual(history.events.filter { $0.title == "Monitoring gap" }.count, 2)
    }

    func testHistoryExpiresAndClearDoesNotImmediatelyReplayState() {
        let history = ActivityHistory()
        record(history, 0, .warning)
        history.clear()
        record(history, 3, .warning)
        XCTAssertTrue(history.events.isEmpty)
        record(history, 6, .critical)
        record(history, 1000, .normal)
        XCTAssertFalse(history.events.contains { $0.date < start.addingTimeInterval(100) })
    }

    func testCapturedContributorsStayUnchangedAndExcludeUnknownTasks() {
        let history = ActivityHistory()
        let records = [
            ProcessRecord(pid: 10, name: "node", path: "/bin/node", directory: "/work/api", memory: 200),
            ProcessRecord(pid: 11, name: "unknown", path: "/bin/unknown", memory: 9999)
        ]
        let workloads = WorkloadGrouper.group(records, apps: [])
        history.record(samples: [SystemSample(date: start, pressure: .warning)], workloads: workloads, ready: true)
        record(history, 3, .warning)
        XCTAssertEqual(history.events.first?.items.map(\.name), ["api"])
        XCTAssertEqual(history.events.first?.items.first?.memory, 200)
    }
    func testSustainedCPUEventsUseCPUOrdering() {
        let history = ActivityHistory()
        let workloads = WorkloadGrouper.group([
            ProcessRecord(pid: 20, name: "node", path: "/bin/node", directory: "/work/cpu", memory: 100, cpu: 60),
            ProcessRecord(pid: 21, name: "node", path: "/bin/node", directory: "/work/memory", memory: 900, cpu: 2)
        ], apps: [])
        let samples = (0..<7).map { SystemSample(date: start.addingTimeInterval(Double($0) * 3), cpu: 95, pressure: .normal) }
        history.record(samples: samples, workloads: workloads, ready: true)
        XCTAssertEqual(history.events.first?.items.first?.name, "cpu")
        XCTAssertEqual(history.events.first?.level, 1)
    }

    func testEventCountIsBoundedDuringRepeatedChanges() {
        let history = ActivityHistory()
        for index in 0..<100 { record(history, Double(index) * 3, index.isMultiple(of: 2) ? .warning : .critical) }
        XCTAssertEqual(history.events.count, 80)
        XCTAssertEqual(history.events.first?.date, start.addingTimeInterval(297))
    }

}
