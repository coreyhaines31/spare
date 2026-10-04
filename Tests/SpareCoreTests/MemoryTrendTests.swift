import XCTest
@testable import SpareCore

final class MemoryTrendTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 10000)
    private let mb: UInt64 = 1024 * 1024
    private func workload(_ memory: UInt64, started: UInt64 = 1, extra: Bool = false) -> [Workload] {
        var processes = [ProcessRecord(pid: 10, started: started, name: "node", path: "/bin/node", directory: "/work/api", memory: memory)]
        if extra { processes.append(ProcessRecord(pid: 11, parent: 10, name: "worker", path: "/bin/worker")) }
        return WorkloadGrouper.group(processes, apps: [])
    }

    func testGrowthNeedsTimeAndMeaningfulAbsoluteAndRelativeChange() throws {
        let tracker = MemoryTrendTracker()
        var trend: MemoryTrend?
        for second in stride(from: 0, through: 60, by: 3) {
            let result = tracker.record(workload(UInt64(500 + second * 5) * mb), at: start.addingTimeInterval(Double(second)), ready: true)
            trend = result["development:/work/api"]
            if second < 60 { XCTAssertFalse(try XCTUnwrap(trend).isGrowing) }
        }
        XCTAssertTrue(try XCTUnwrap(trend).isGrowing)
        XCTAssertEqual(trend?.change, Int64(300 * mb))
        XCTAssertEqual(trend?.summary, "Up 300 MB over 60 seconds")
        let large = MemoryTrend(points: [MemoryPoint(date: start, bytes: 10000 * mb), MemoryPoint(date: start.addingTimeInterval(60), bytes: 10300 * mb)], membershipChanged: false)
        XCTAssertFalse(large.isGrowing)
    }

    func testRestartAndSamplingGapResetBaseline() throws {
        let tracker = MemoryTrendTracker()
        _ = tracker.record(workload(100 * mb), at: start, ready: true)
        let restarted = tracker.record(workload(600 * mb, started: 2), at: start.addingTimeInterval(3), ready: true)
        XCTAssertEqual(restarted["development:/work/api"]?.change, 0)
        let afterGap = tracker.record(workload(900 * mb, started: 2), at: start.addingTimeInterval(60), ready: true)
        XCTAssertEqual(afterGap["development:/work/api"]?.points.count, 1)
        XCTAssertTrue(tracker.record(workload(900 * mb), at: start.addingTimeInterval(63), ready: false).isEmpty)
    }

    func testMembershipChangesAreVisibleAndHistoryIsBounded() {
        let tracker = MemoryTrendTracker()
        var result: [String: MemoryTrend] = [:]
        for index in 0..<150 {
            result = tracker.record(workload(100 * mb, extra: index > 100), at: start.addingTimeInterval(Double(index) * 3), ready: true)
        }
        XCTAssertEqual(result["development:/work/api"]?.points.count, 101)
        XCTAssertEqual(result["development:/work/api"]?.membershipChanged, true)
        XCTAssertTrue(tracker.record([], at: start.addingTimeInterval(450), ready: true).isEmpty)
    }
    func testAppRestartResetsEvenWhenAHelperSurvives() throws {
        let tracker = MemoryTrendTracker()
        let app = AppRecord(pid: 20, name: "Browser", path: "/Applications/Browser.app", canQuit: true)
        func groups(_ started: UInt64, _ memory: UInt64) -> [Workload] {
            WorkloadGrouper.group([
                ProcessRecord(pid: 20, started: started, name: "Browser", path: app.path + "/Contents/MacOS/Browser", memory: memory),
                ProcessRecord(pid: 21, parent: 20, name: "Helper", path: app.path + "/Contents/MacOS/Helper", memory: 50 * mb)
            ], apps: [app])
        }
        _ = tracker.record(groups(1, 100 * mb), at: start, ready: true)
        let result = tracker.record(groups(2, 500 * mb), at: start.addingTimeInterval(3), ready: true)
        XCTAssertEqual(result["app:/Applications/Browser.app"]?.change, 0)
    }

    func testTrackingBudgetAndMemoryDecrease() {
        let tracker = MemoryTrendTracker()
        let processes = (1...300).map {
            ProcessRecord(pid: Int32($0), parent: 9999, name: "node", path: "/bin/node", directory: "/work/\($0)", memory: mb)
        }
        let groups = WorkloadGrouper.group(processes, apps: [])
        XCTAssertEqual(tracker.record(groups, at: start, ready: true).count, 256)
        let shrinking = MemoryTrend(points: [MemoryPoint(date: start, bytes: 500 * mb), MemoryPoint(date: start.addingTimeInterval(60), bytes: 100 * mb)], membershipChanged: false)
        XCTAssertFalse(shrinking.isGrowing)
        XCTAssertEqual(shrinking.summary, "Down 400 MB over 60 seconds")
    }

}
