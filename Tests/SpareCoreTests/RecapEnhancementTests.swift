import XCTest
@testable import SpareCore

final class RecapEnhancementTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return value
    }
    private var start: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 17, minute: 23))! }
    private func workloads(_ name: String = "agent") -> [Workload] {
        [Workload(id: "test", name: name, subtitle: "", explanation: "", consequence: "", kind: .agent,
            processes: [ProcessRecord(pid: 1, name: "agent", path: "/private/path", memory: 1_000, cpu: 25)], canStop: false)]
    }
    private func sample(_ tracker: AwayRecapTracker, seconds: Double, idle: Double, enabled: Bool = true) {
        let now = start.addingTimeInterval(seconds)
        tracker.record(SystemSample(date: now, cpu: 50, pressure: .warning), workloads: workloads(), idleSeconds: idle, ready: true, enabled: enabled, now: now)
    }
    func testAwaySummaryCountsOnlyObservedTimeAfterThreshold() throws {
        let tracker = AwayRecapTracker()
        sample(tracker, seconds: 0, idle: 0)
        sample(tracker, seconds: 297, idle: 297)
        for time in stride(from: 300.0, through: 360, by: 3) { sample(tracker, seconds: time, idle: time) }
        sample(tracker, seconds: 363, idle: 0)
        let summary = try XCTUnwrap(tracker.latest)
        XCTAssertEqual(summary.report.totals.observed, 60, accuracy: 0.001)
        XCTAssertEqual(summary.report.totals.pressureSeconds, 60, accuracy: 0.001)
        XCTAssertEqual(summary.report.interval.start, start.addingTimeInterval(300))
        XCTAssertEqual(summary.leaders.first?.name, "agent")
        tracker.dismiss()
        XCTAssertNil(tracker.latest)
    }
    func testShortAbsenceAndSleepOnlyDoNotCreateRecap() {
        let tracker = AwayRecapTracker()
        sample(tracker, seconds: 300, idle: 300)
        sample(tracker, seconds: 303, idle: 303)
        tracker.pause()
        sample(tracker, seconds: 3600, idle: 0)
        XCTAssertNil(tracker.latest)
    }
    func testShortExplicitSleepGapIsNotCredited() throws {
        let tracker = AwayRecapTracker()
        for time in stride(from: 300.0, through: 330, by: 3) { sample(tracker, seconds: time, idle: time) }
        tracker.pause()
        for time in stride(from: 336.0, through: 366, by: 3) { sample(tracker, seconds: time, idle: time) }
        sample(tracker, seconds: 369, idle: 0)
        XCTAssertEqual(try XCTUnwrap(tracker.latest).report.totals.observed, 60, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(tracker.latest).report.unobserved, 9, accuracy: 0.001)
        sample(tracker, seconds: 372, idle: 0, enabled: false)
        XCTAssertNil(tracker.latest)
    }
    func testLastSevenDaysAndComparisonDoNotOverlap() {
        let interval = RecapPeriod.lastSevenDays.interval(at: start, calendar: calendar)
        XCTAssertEqual(calendar.component(.day, from: interval.start), 28)
        XCTAssertEqual(calendar.component(.month, from: interval.start), 9)
        let previous = RecapPeriod.lastSevenDays.interval(at: interval.start.addingTimeInterval(-1), calendar: calendar)
        XCTAssertEqual(previous.end, interval.start)
        XCTAssertEqual(calendar.dateComponents([.day], from: previous.start, to: previous.end).day, 7)
        let dstDate = calendar.date(from: DateComponents(year: 2026, month: 11, day: 3))!
        XCTAssertEqual(RecapPeriod.lastSevenDays.interval(at: dstDate, calendar: calendar).duration, 169 * 3600)
    }
    func testCSVQuotesNamesNeutralizesFormulasAndUsesStableNumbers() {
        let history = RecapHistory()
        for offset in [0.0, 3] {
            history.record(SystemSample(date: start.addingTimeInterval(offset), cpu: 50, pressure: .warning),
                           workloads: workloads(" =HYPERLINK(\"x\"),\nagent"), ready: true)
        }
        let report = history.report(.today, at: start.addingTimeInterval(4), calendar: calendar)
        let csv = RecapCSV.make(report)
        XCTAssertTrue(csv.contains("\"' =HYPERLINK(\"\"x\"\"),\nagent\""))
        XCTAssertTrue(csv.contains("\"50.000\""))
        XCTAssertTrue(csv.contains("\"25.000\""))
        XCTAssertFalse(csv.contains("/private/path"))
        XCTAssertTrue(csv.hasSuffix("\r\n"))
    }
}
