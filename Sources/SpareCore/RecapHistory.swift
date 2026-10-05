import Foundation
import CryptoKit

public final class RecapHistory {
    public private(set) var buckets: [RecapBucket]
    private var previous: SystemSample?
    private var previousWorkloads: [Workload] = []
    public init(buckets: [RecapBucket] = []) { self.buckets = buckets.sorted { $0.start < $1.start } }
    public func pause() { previous = nil; previousWorkloads = [] }
    public func clear() { buckets = []; pause() }
    public func prune(at date: Date) {
        let cutoff = date.addingTimeInterval(-30 * 86400)
        buckets.removeAll { $0.start < cutoff }
    }
    public func record(_ sample: SystemSample, workloads: [Workload], ready: Bool, calendar: Calendar = .current) {
        prune(at: sample.date)
        guard ready else { pause(); return }
        defer { previous = sample; previousWorkloads = workloads }
        guard let old = previous else { return }
        let elapsed = sample.date.timeIntervalSince(old.date)
        guard elapsed > 0, elapsed <= 10, old.date >= (buckets.last?.recordedThrough ?? .distantPast) else { return }
        var cursor = old.date
        while cursor < sample.date {
            guard let hour = calendar.dateInterval(of: .hour, for: cursor) else { break }
            let end = min(hour.end, sample.date)
            let seconds = end.timeIntervalSince(cursor)
            if buckets.last?.start != hour.start {
                // Clock changes never add overlapping coverage to an existing hour.
                if buckets.contains(where: { $0.start >= hour.start }) { pause(); return }
                buckets.append(RecapBucket(start: hour.start, end: hour.end))
            }
            let index = buckets.count - 1
            buckets[index].recordedThrough = end
            buckets[index].totals.add(RecapTotals(observed: seconds, cpuSeconds: sample.cpu * seconds,
                busySeconds: sample.cpu > 85 ? seconds : 0,
                pressureSeconds: old.pressure == .warning || old.pressure == .critical ? seconds : 0,
                knownPressureSeconds: old.pressure == .unknown ? 0 : seconds, peakCPU: sample.cpu))
            recordWorkloads(previousWorkloads, seconds: seconds, pressure: old.pressure, index: index)
            cursor = end
        }
    }
    private func recordWorkloads(_ workloads: [Workload], seconds: Double, pressure: MemoryPressure, index: Int) {
        for workload in workloads where workload.kind != .background {
            let id = Self.workloadID(workload.id)
            var entry = buckets[index].workloads[id] ?? RecapWorkload(id: id, name: String(workload.name.prefix(160)), kind: workload.kind)
            entry.observed += seconds
            entry.cpuSeconds += workload.cpu * seconds
            entry.memoryByteSeconds += Double(workload.memory) * seconds
            entry.peakMemory = max(entry.peakMemory, workload.memory)
            if pressure == .warning || pressure == .critical { entry.pressureByteSeconds += Double(workload.memory) * seconds }
            buckets[index].workloads[id] = entry
        }
        if buckets[index].workloads.count > 128 {
            let ranked = buckets[index].workloads.values.sorted {
                let left = $0.cpuSeconds + $0.memoryByteSeconds / 1_073_741_824
                let right = $1.cpuSeconds + $1.memoryByteSeconds / 1_073_741_824
                return left == right ? $0.id < $1.id : left > right
            }.prefix(128)
            buckets[index].workloads = Dictionary(uniqueKeysWithValues: ranked.map { ($0.id, $0) })
        }
    }
    public func report(_ period: RecapPeriod, at now: Date, calendar: Calendar = .current) -> RecapReport {
        let full = period.interval(at: now, calendar: calendar)
        let interval = DateInterval(start: full.start, end: now)
        let previousDate = full.start.addingTimeInterval(-1)
        let previousInterval = period.interval(at: previousDate, calendar: calendar)
        return report(in: interval, comparedWith: previousInterval)
    }
    public static func workloadID(_ id: String) -> String {
        SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    public func report(in interval: DateInterval, comparedWith previousInterval: DateInterval? = nil) -> RecapReport {
        let current = aggregate(interval)
        return RecapReport(interval: interval, totals: current.0, previous: previousInterval.map { aggregate($0).0 } ?? RecapTotals(),
                           workloads: Array(current.1.values), buckets: buckets.filter {
            $0.start < interval.end && $0.end > interval.start && ($0.recordedThrough ?? $0.end) <= interval.end
        })
    }
    private func aggregate(_ interval: DateInterval) -> (RecapTotals, [String: RecapWorkload]) {
        var totals = RecapTotals()
        var workloads: [String: RecapWorkload] = [:]
        for bucket in buckets where bucket.start < interval.end && bucket.end > interval.start && (bucket.recordedThrough ?? bucket.end) <= interval.end {
            // Current-hour totals already contain only observed time, not the remainder of the hour.
            let fraction = bucket.start >= interval.start ? 1 : min(1, bucket.end.timeIntervalSince(interval.start) / bucket.end.timeIntervalSince(bucket.start))
            totals.add(bucket.totals, fraction: fraction)
            for item in bucket.workloads.values {
                var total = workloads[item.id] ?? RecapWorkload(id: item.id, name: item.name, kind: item.kind)
                total.add(item, fraction: fraction)
                workloads[item.id] = total
            }
        }
        return (totals, workloads)
    }
}
