import XCTest
import Darwin
import CSpare
@testable import SpareCore

final class CPUTimeTests: XCTestCase {
    private func processTime() -> Double {
        var time = timespec()
        clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &time)
        return Double(time.tv_sec) * 1_000_000_000 + Double(time.tv_nsec)
    }
    func testNativeCPUCounterUsesNanosecondsOnThisArchitecture() {
        var before = SpareProcess()
        var after = SpareProcess()
        XCTAssertTrue(spare_process(getpid(), &before, false))
        let start = processTime()
        while processTime() - start < 100_000_000 {}
        let duration = processTime() - start
        XCTAssertTrue(spare_process(getpid(), &after, false))
        let measured = Double(after.cpu_ns - before.cpu_ns)
        XCTAssertEqual(measured / duration, 1, accuracy: 0.15)
    }
    func testLegacyRecapMigrationOnlyScalesWorkloadCPU() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("recaps.json")
        let now = Date()
        let history = RecapHistory()
        let workloads = WorkloadGrouper.group([ProcessRecord(pid: 10, name: "node", path: "/bin/node", directory: "/work/api", memory: 100, cpu: 1)], apps: [])
        for offset in [-3.0, 0.0] {
            history.record(SystemSample(date: now.addingTimeInterval(offset), cpu: 50, pressure: .normal), workloads: workloads, ready: true)
        }
        let encoded = try JSONEncoder().encode(history.buckets)
        let legacy: [String: Any] = ["version": 1, "buckets": try JSONSerialization.jsonObject(with: encoded)]
        try JSONSerialization.data(withJSONObject: legacy).write(to: url)
        let store = RecapStore(url: url, now: now)
        let report = store.history.report(.today, at: now)
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        XCTAssertEqual(report.workloads.first?.cpuSeconds ?? 0, 3 * Double(timebase.numer) / Double(timebase.denom), accuracy: 0.001)
        XCTAssertEqual(report.totals.averageCPU, 50)
        XCTAssertEqual(report.workloads.first?.memoryByteSeconds, 300)
        store.save(at: now)
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(saved["version"] as? Int, 2)
        let reloaded = RecapStore(url: url, now: now).history.report(.today, at: now)
        XCTAssertEqual(reloaded.workloads.first?.cpuSeconds, report.workloads.first?.cpuSeconds)
    }
}
