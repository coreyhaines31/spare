import XCTest
@testable import SpareCore

final class RecapCalendarTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        value.firstWeekday = 2
        return value
    }
    private func date(_ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }
    private func add(_ history: RecapHistory, at date: Date, cpu: Double) {
        history.record(SystemSample(date: date, cpu: cpu, pressure: .normal), workloads: [], ready: true, calendar: calendar)
        history.record(SystemSample(date: date.addingTimeInterval(6), cpu: cpu, pressure: .normal), workloads: [], ready: true, calendar: calendar)
    }
    func testCalendarWeekIncludesCurrentDaysAndSeparatePreviousWeek() {
        let history = RecapHistory()
        add(history, at: date(1), cpu: 20)
        add(history, at: date(5), cpu: 50)
        add(history, at: date(6), cpu: 80)
        let report = history.report(.week, at: date(7), calendar: calendar)
        XCTAssertEqual(report.totals.observed, 12)
        XCTAssertEqual(report.totals.averageCPU, 65)
        XCTAssertEqual(report.previous.observed, 6)
        XCTAssertEqual(report.previous.averageCPU, 20)
        XCTAssertEqual(report.buckets.count, 2)
    }
    func testFallBackKeepsRepeatedHoursDistinctAndUses25HourDay() {
        let history = RecapHistory()
        let first = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 1, minute: 30))!
        add(history, at: first, cpu: 20)
        add(history, at: first.addingTimeInterval(3600), cpu: 60)
        let end = calendar.date(from: DateComponents(year: 2026, month: 11, day: 2))!
        let report = history.report(.today, at: end.addingTimeInterval(-1), calendar: calendar)
        XCTAssertEqual(history.buckets.count, 2)
        XCTAssertEqual(report.totals.observed, 12)
        XCTAssertEqual(report.totals.averageCPU, 40)
        XCTAssertEqual(report.interval.duration, 25 * 3600 - 1)
    }
    func testPausedRecordingDoesNotBridgeTheGap() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("recaps.json")
        let start = date(5)
        let store = RecapStore(url: url, now: start)
        for (seconds, enabled) in [(0, true), (3, true), (6, false), (9, true), (12, true)] {
            let now = start.addingTimeInterval(Double(seconds))
            store.record(SystemSample(date: now, cpu: 30), workloads: [], ready: true, enabled: enabled, now: now)
        }
        store.save(at: start.addingTimeInterval(12))
        XCTAssertEqual(store.history.report(.today, at: start.addingTimeInterval(13), calendar: calendar).totals.observed, 6)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o600)
    }
    func testWriteFailureIsVisibleAndDoesNotDiscardInMemoryHistory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let parentFile = directory.appendingPathComponent("file")
        try Data().write(to: parentFile)
        let store = RecapStore(url: parentFile.appendingPathComponent("recaps.json"), now: date(5))
        add(store.history, at: date(5), cpu: 50)
        store.save(at: date(5).addingTimeInterval(10))
        XCTAssertNotNil(store.error)
        XCTAssertEqual(store.history.buckets.first?.totals.observed, 6)
        XCTAssertFalse(store.clear())
        XCTAssertEqual(store.history.buckets.first?.totals.observed, 6)
    }
}
