import Foundation

public struct AwayRecap: Identifiable {
    public let id = UUID()
    public let report: RecapReport
    public var ended: Date { report.interval.end }
    public var leaders: [RecapWorkload] {
        Array(report.workloads.sorted {
            let left = report.totals.pressureSeconds > 0 ? $0.pressureByteSeconds : $0.cpuSeconds
            let right = report.totals.pressureSeconds > 0 ? $1.pressureByteSeconds : $1.cpuSeconds
            return left == right ? $0.id < $1.id : left > right
        }.prefix(3))
    }
}

public final class AwayRecapTracker {
    public private(set) var latest: AwayRecap?
    private let history = RecapHistory()
    private var start: Date?
    private var previousDate: Date?
    public init() {}
    public func pause() { history.pause(); previousDate = nil }
    public func clear() { latest = nil; start = nil; history.clear(); previousDate = nil }
    public func dismiss() { latest = nil }
    public func record(_ sample: SystemSample?, workloads: [Workload], idleSeconds: Double, ready: Bool, enabled: Bool, now: Date) {
        guard enabled else { clear(); return }
        if let latest, now.timeIntervalSince(latest.ended) > 18 * 3600 || now < latest.ended { self.latest = nil }
        guard let sample, ready, idleSeconds.isFinite, idleSeconds >= 0 else { pause(); return }
        if let previousDate, sample.date <= previousDate { clear() }
        previousDate = sample.date
        if idleSeconds >= 300 {
            if start == nil { start = sample.date; history.clear() }
            history.record(sample, workloads: workloads, ready: true)
        } else if let start {
            // Stop at the preceding observation; returning input is never credited as away work.
            let end = sample.date.addingTimeInterval(-idleSeconds)
            if end > start {
                var report = history.report(in: DateInterval(start: history.buckets.first?.start ?? start, end: end))
                report.interval = DateInterval(start: start, end: end)
                if report.totals.observed >= 60 { latest = AwayRecap(report: report) }
            }
            self.start = nil
            history.clear()
        }
    }
}
