import XCTest
@testable import SpareCore

final class RecapTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }
    private let start = Date(timeIntervalSince1970: 1_780_272_000)
    private func workloads(cpu: Double = 40, memory: UInt64 = 1_000) -> [Workload] {
        WorkloadGrouper.group([ProcessRecord(pid: 10, name: "node", path: "/bin/node",
            directory: "/private/project", memory: memory, cpu: cpu)], apps: [])
    }
    private func record(_ history: RecapHistory, at date: Date, cpu: Double = 50, pressure: MemoryPressure = .warning, ready: Bool = true) {
        history.record(SystemSample(date: date, cpu: cpu, pressure: pressure), workloads: workloads(), ready: ready, calendar: calendar)
    }
    func testWeightedTotalsPressureAndWorkloads() {
        let history = RecapHistory()
        record(history, at: start, cpu: 10)
        record(history, at: start.addingTimeInterval(3), cpu: 20)
        record(history, at: start.addingTimeInterval(9), cpu: 80)
        let report = history.report(.today, at: start.addingTimeInterval(10), calendar: calendar)
        XCTAssertEqual(report.totals.observed, 9)
        XCTAssertEqual(report.totals.averageCPU, 60, accuracy: 0.001)
        XCTAssertEqual(report.totals.pressureSeconds, 9)
        XCTAssertEqual(report.workloads.first?.cpuSeconds, 360)
        XCTAssertEqual(report.workloads.first?.memoryByteSeconds, 9_000)
        XCTAssertEqual(report.workloads.first?.name, "project")
        XCTAssertFalse(report.workloads.first?.id.contains("private") ?? true)
    }
    func testGapsUnknownPressureAndNotReadyAreNotCounted() {
        let history = RecapHistory()
        record(history, at: start, pressure: .unknown)
        record(history, at: start.addingTimeInterval(3), pressure: .unknown)
        record(history, at: start.addingTimeInterval(100))
        record(history, at: start.addingTimeInterval(103), ready: false)
        record(history, at: start.addingTimeInterval(106))
        record(history, at: start.addingTimeInterval(109))
        let report = history.report(.today, at: start.addingTimeInterval(110), calendar: calendar)
        XCTAssertEqual(report.totals.observed, 6)
        XCTAssertEqual(report.totals.knownPressureSeconds, 3)
        XCTAssertEqual(report.totals.pressureSeconds, 3)
        XCTAssertGreaterThan(report.unobserved, 100)
    }
    func testMidnightSplitsTimeAndPreviousDayComparison() {
        let midnight = calendar.startOfDay(for: start).addingTimeInterval(86400)
        let history = RecapHistory()
        record(history, at: midnight.addingTimeInterval(-2))
        record(history, at: midnight.addingTimeInterval(4))
        let report = history.report(.today, at: midnight.addingTimeInterval(5), calendar: calendar)
        XCTAssertEqual(report.totals.observed, 4)
        XCTAssertEqual(report.previous.observed, 2)
        XCTAssertEqual(history.buckets.count, 2)
    }
    func testRollbackDoesNotDoubleCount() {
        let history = RecapHistory()
        for second in [0, 3, 6, 2, 5, 8, 11] { record(history, at: start.addingTimeInterval(Double(second))) }
        XCTAssertEqual(history.report(.today, at: start.addingTimeInterval(12), calendar: calendar).totals.observed, 9)
    }
    func testStoreSurvivesRestartWithoutCountingOfflineTimeAndClearPersists() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("recaps.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RecapStore(url: url, now: start)
        record(store.history, at: start)
        record(store.history, at: start.addingTimeInterval(3))
        store.save(at: start.addingTimeInterval(3))
        XCTAssertNil(store.error)
        let data = try String(contentsOf: url)
        XCTAssertFalse(data.contains("/private/"))
        XCTAssertFalse(data.contains("processes"))
        let restored = RecapStore(url: url, now: start.addingTimeInterval(100))
        record(restored.history, at: start.addingTimeInterval(100))
        record(restored.history, at: start.addingTimeInterval(103))
        XCTAssertEqual(restored.history.buckets.first?.totals.observed, 6)
        XCTAssertTrue(restored.clear())
        XCTAssertTrue(RecapStore(url: url, now: start).history.buckets.isEmpty)
    }
    func testCorruptArchiveIsPreservedUntilExplicitClear() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("recaps.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("broken".utf8).write(to: url)
        let store = RecapStore(url: url, now: start)
        store.save(at: start)
        XCTAssertNotNil(store.error)
        XCTAssertEqual(try String(contentsOf: url), "broken")
        XCTAssertTrue(store.clear())
        XCTAssertNil(store.error)
    }
    func testRetentionAndHourlyWorkloadLimit() {
        let history = RecapHistory()
        let many = (0..<200).map { ProcessRecord(pid: Int32($0 + 10), name: "node", path: "/bin/node", directory: "/work/\($0)", memory: UInt64($0 + 1)) }
        let grouped = WorkloadGrouper.group(many, apps: [])
        history.record(SystemSample(date: start), workloads: grouped, ready: true, calendar: calendar)
        history.record(SystemSample(date: start.addingTimeInterval(3)), workloads: grouped, ready: true, calendar: calendar)
        XCTAssertEqual(history.buckets.first?.workloads.count, 128)
        history.prune(at: start.addingTimeInterval(31 * 86400))
        XCTAssertTrue(history.buckets.isEmpty)
    }
}
