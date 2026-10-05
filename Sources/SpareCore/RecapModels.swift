import Foundation

public enum RecapPeriod: String, CaseIterable {
    case today = "Today", week = "This week", lastSevenDays = "Last 7 days"
    public var comparisonLabel: String {
        switch self {
        case .today: return "yesterday"
        case .week: return "last week"
        case .lastSevenDays: return "the previous 7 days"
        }
    }
    public func interval(at date: Date, calendar: Calendar) -> DateInterval {
        if self == .lastSevenDays {
            let today = calendar.startOfDay(for: date)
            return DateInterval(start: calendar.date(byAdding: .day, value: -6, to: today)!,
                                end: calendar.date(byAdding: .day, value: 1, to: today)!)
        }
        return calendar.dateInterval(of: self == .today ? .day : .weekOfYear, for: date)!
    }
}

public struct RecapTotals: Codable {
    public var observed: Double = 0
    public var cpuSeconds: Double = 0
    public var busySeconds: Double = 0
    public var pressureSeconds: Double = 0
    public var knownPressureSeconds: Double = 0
    public var peakCPU: Double = 0
    public var averageCPU: Double { observed > 0 ? cpuSeconds / observed : 0 }
    public var pressurePercent: Double? { knownPressureSeconds > 0 ? 100 * pressureSeconds / knownPressureSeconds : nil }
    mutating func add(_ other: Self, fraction: Double = 1) {
        observed += other.observed * fraction
        cpuSeconds += other.cpuSeconds * fraction
        busySeconds += other.busySeconds * fraction
        pressureSeconds += other.pressureSeconds * fraction
        knownPressureSeconds += other.knownPressureSeconds * fraction
        peakCPU = max(peakCPU, other.peakCPU)
    }
}

public struct RecapWorkload: Codable, Identifiable {
    public var id: String
    public var name: String
    public var kind: WorkloadKind
    public var observed: Double = 0
    public var cpuSeconds: Double = 0
    public var memoryByteSeconds: Double = 0
    public var peakMemory: UInt64 = 0
    public var pressureByteSeconds: Double = 0
    mutating func add(_ other: Self, fraction: Double = 1) {
        observed += other.observed * fraction
        cpuSeconds += other.cpuSeconds * fraction
        memoryByteSeconds += other.memoryByteSeconds * fraction
        pressureByteSeconds += other.pressureByteSeconds * fraction
        peakMemory = max(peakMemory, other.peakMemory)
    }
}

public struct RecapBucket: Codable, Identifiable {
    public var start: Date
    public var end: Date
    public var recordedThrough: Date?
    public var totals = RecapTotals()
    public var workloads: [String: RecapWorkload] = [:]
    public var id: Date { start }
}

public struct RecapReport {
    public var interval: DateInterval
    public var totals: RecapTotals
    public var previous: RecapTotals
    public var workloads: [RecapWorkload]
    public var buckets: [RecapBucket]
    public var unobserved: Double { max(0, interval.duration - totals.observed) }
    public var summary: String {
        guard totals.observed >= 60 else { return "Gathering your first minute of history. Recaps start when Spare is running; earlier activity cannot be recovered." }
        guard totals.knownPressureSeconds > 0 else { return "CPU readings were recorded, but macOS memory pressure was unavailable." }
        guard totals.pressureSeconds > 0 else { return "No elevated memory pressure was observed during the recorded time." }
        let leaders = workloads.filter { $0.pressureByteSeconds > 0 }.sorted { $0.pressureByteSeconds > $1.pressureByteSeconds }.prefix(2).map(\.name)
        let detail = leaders.isEmpty ? "" : " \(leaders.joined(separator: " and ")) had the largest recorded memory footprints during those periods."
        return "Memory pressure was elevated for \(RecapFormat.duration(totals.pressureSeconds))." + detail
    }
}

public enum RecapFormat {
    public static func cpu(_ value: Double) -> String {
        value > 0 && value < 0.1 ? "<0.1%" : String(format: "%.1f%%", value)
    }

    public static func duration(_ seconds: Double) -> String {
        if seconds < 60 { return seconds > 0 ? "less than a minute" : "0 min" }
        let minutes = Int(seconds / 60)
        return minutes < 60 ? "\(minutes) min" : "\(minutes / 60) hr \(minutes % 60) min"
    }
}
