import Foundation

public struct MemoryPoint {
    public let date: Date
    public let bytes: UInt64
}

public struct MemoryTrend {
    public let points: [MemoryPoint]
    public let membershipChanged: Bool
    public var duration: TimeInterval { (points.last?.date ?? .distantPast).timeIntervalSince(points.first?.date ?? .distantPast) }
    public var change: Int64 {
        Int64(clamping: points.last?.bytes ?? 0) - Int64(clamping: points.first?.bytes ?? 0)
    }
    public var isGrowing: Bool {
        guard duration >= 60, let first = points.first else { return false }
        return change >= 256 * 1024 * 1024 && Double(change) >= Double(first.bytes) * 0.25
    }
    public var summary: String {
        guard duration >= 60 else { return "Gathering a minute of memory readings…" }
        let interval = duration < 120 ? "\(Int(duration)) seconds" : "\(Int(duration / 60)) minutes"
        if abs(change) < 1024 * 1024 { return "Little net change over \(interval)" }
        return "\(change > 0 ? "Up" : "Down") \(DisplayFormat.memory(UInt64(abs(change)))) over \(interval)"
    }
}

public final class MemoryTrendTracker {
    private struct Series {
        var points: [MemoryPoint]
        var identities: Set<ProcessIdentity>
        var appIdentity: ProcessIdentity?
        var changedAt: Date?
    }
    private var series: [String: Series] = [:]
    public init() {}
    public func reset() { series.removeAll() }

    public func record(_ workloads: [Workload], at date: Date, ready: Bool) -> [String: MemoryTrend] {
        guard ready else { reset(); return [:] }
        let identified = workloads.filter { $0.kind != .background }
        let tracked = (identified + identified.flatMap(\.sessions)).sorted {
            $0.memory == $1.memory ? $0.id < $1.id : $0.memory > $1.memory
        }.prefix(256)
        let ids = Set(tracked.map(\.id))
        series = series.filter { ids.contains($0.key) }
        for workload in tracked {
            let identities = Set(workload.processes.map(\.identity))
            var previous = series[workload.id]
            if let old = previous, let last = old.points.last,
               date.timeIntervalSince(last.date) > 10 || date <= last.date ||
                old.identities.isDisjoint(with: identities) || old.appIdentity != workload.appIdentity {
                previous = nil
            }
            var entry = previous ?? Series(points: [], identities: identities, appIdentity: workload.appIdentity)
            if entry.identities != identities { entry.changedAt = date }
            entry.identities = identities
            entry.points.removeAll { date.timeIntervalSince($0.date) > 300 }
            entry.points.append(MemoryPoint(date: date, bytes: workload.memory))
            if entry.points.count > 101 { entry.points.removeFirst(entry.points.count - 101) }
            series[workload.id] = entry
        }
        return series.mapValues { entry in
            MemoryTrend(points: entry.points, membershipChanged: entry.changedAt.map { date.timeIntervalSince($0) <= 300 } ?? false)
        }
    }
}
