import Foundation

public struct ActivityItem: Identifiable {
    public let id: String
    public let name: String
    public let memory: UInt64
    public let cpu: Double
}

public struct ActivityEvent: Identifiable {
    public let id = UUID()
    public let date: Date
    public let title: String
    public let message: String
    public let level: Int
    public let items: [ActivityItem]
}

public final class ActivityHistory {
    public private(set) var events: [ActivityEvent] = []
    private var state: String?
    private var lastDate: Date?
    private var healthySince: Date?
    public init() {}

    public func pause(at date: Date) {
        prune(at: date)
        if state != nil {
            append(date, "Monitoring gap", "Readings were interrupted. Spare cannot describe what happened during this gap.", level: 0)
        }
        state = nil
        healthySince = nil
        lastDate = nil
    }

    public func record(samples: [SystemSample], workloads: [Workload], ready: Bool) {
        guard let sample = samples.last else { return }
        prune(at: sample.date)
        guard ready else { pause(at: sample.date); return }
        if let lastDate, sample.date.timeIntervalSince(lastDate) > 10 || sample.date <= lastDate {
            pause(at: sample.date)
        }
        lastDate = sample.date
        let health = Health(samples: samples, ready: true)
        let next = sample.pressure == .critical ? "critical" : sample.pressure == .warning ? "warning" :
            health.level > 0 ? "cpu" : sample.pressure == .unknown ? "unknown" : "normal"
        guard next != state else { healthySince = nil; return }
        if next == "normal", let state, state != "unknown" {
            if healthySince == nil { healthySince = sample.date }
            guard let healthySince, sample.date.timeIntervalSince(healthySince) >= 30 else { return }
        } else { healthySince = nil }
        let previous = state
        state = next
        let recovering = next == "normal" && previous != nil && previous != "unknown"
        if next == "normal" || next == "unknown" {
            append(sample.date, recovering ? "Pressure eased" : next == "unknown" ? "Memory pressure unavailable" : previous == "unknown" ? "Memory pressure available" : "Monitoring started",
                   recovering ? "No sustained CPU warning or elevated memory pressure has been detected for 30 seconds." : health.message, level: 0)
            return
        }
        let memoryConcern = next == "warning" || next == "critical"
        let items = workloads.filter { $0.kind != .background }.sorted {
            memoryConcern ? $0.memory > $1.memory : $0.cpu > $1.cpu
        }.prefix(3).map { ActivityItem(id: $0.id, name: $0.name, memory: $0.memory, cpu: $0.cpu) }
        events.insert(ActivityEvent(date: sample.date, title: health.title,
            message: memoryConcern ? "Largest identified memory users at this reading. These readings do not establish the cause of the pressure." :
                "Largest identified CPU users when sustained load was detected. Busy work may be intentional.", level: health.level, items: items), at: 0)
        prune(at: sample.date)
    }

    public func clear() { events.removeAll() }

    private func append(_ date: Date, _ title: String, _ message: String, level: Int) {
        events.insert(ActivityEvent(date: date, title: title, message: message, level: level, items: []), at: 0)
        prune(at: date)
    }

    private func prune(at date: Date) {
        events.removeAll { date.timeIntervalSince($0.date) > 900 || $0.date > date }
        if events.count > 80 { events.removeLast(events.count - 80) }
    }
}
