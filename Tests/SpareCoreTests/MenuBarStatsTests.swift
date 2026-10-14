import XCTest
@testable import SpareCore

final class MenuBarStatsTests: XCTestCase {
    func testKeepsAFixedOrder() {
        XCTAssertEqual(MenuBarStat.ordered([.disk, .cpu, .memory]), [.cpu, .memory, .disk])
        XCTAssertEqual(MenuBarStat.ordered([]), [])
    }

    func testReadsPercentagesFromASystemSample() {
        let system = SystemSample(cpu: 18.4, memory: 87, physical: 100)
        let readings = MenuBarReadings(system: system, ready: true, gpu: 37.6, disk: 70)
        XCTAssertEqual(MenuBarStat.allCases.map(readings.text), ["18%", "38%", "87%", "70%"])
    }

    func testShowsADashUntilThereIsAReading() {
        let readings = MenuBarReadings(system: SystemSample(cpu: 0, memory: 50, physical: 100), ready: false, gpu: nil, disk: nil)
        XCTAssertEqual(readings.text(.cpu), "–")
        XCTAssertEqual(readings.text(.gpu), "–")
        XCTAssertEqual(readings.text(.memory), "50%")
        XCTAssertEqual(MenuBarReadings(system: nil, ready: true, gpu: nil, disk: nil).text(.memory), "–")
    }

    func testClampsOutOfRangeValues() {
        XCTAssertEqual(MenuBarReadings(gpu: 104).text(.gpu), "100%")
        XCTAssertEqual(MenuBarReadings(gpu: -3).text(.gpu), "0%")
    }

    func testDiskUsageCountsPurgeableSpaceAsFree() {
        XCTAssertEqual(DiskUsage.percentUsed(total: 1000, available: 300), 70)
        XCTAssertEqual(DiskUsage.percentUsed(total: 1000, available: 1200), 0)
    }
}
