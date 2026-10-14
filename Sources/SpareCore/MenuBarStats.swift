import Foundation
import IOKit

/// A reading someone can choose to show next to the Spare icon.
public enum MenuBarStat: String, CaseIterable, Codable {
    case cpu, gpu, memory, disk

    /// The short label drawn above the number in the menu bar.
    public var label: String {
        switch self {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: "RAM"
        case .disk: "SSD"
        }
    }

    /// The name shown in settings.
    public var title: String {
        switch self {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: "Memory"
        case .disk: "Startup disk"
        }
    }

    /// Keeps the menu bar order fixed no matter the order they were turned on.
    public static func ordered(_ stats: Set<MenuBarStat>) -> [MenuBarStat] { allCases.filter(stats.contains) }
}

/// The latest percentages for the menu bar. A missing value shows as a dash.
public struct MenuBarReadings: Equatable {
    public var cpu: Double?
    public var gpu: Double?
    public var memory: Double?
    public var disk: Double?

    public init(cpu: Double? = nil, gpu: Double? = nil, memory: Double? = nil, disk: Double? = nil) {
        self.cpu = cpu
        self.gpu = gpu
        self.memory = memory
        self.disk = disk
    }

    public init(system: SystemSample?, ready: Bool, gpu: Double?, disk: Double?) {
        self.init(gpu: gpu, disk: disk)
        guard let system else { return }
        if ready { cpu = system.cpu }
        if system.physical > 0 { memory = 100 * Double(system.memory) / Double(system.physical) }
    }

    public func value(_ stat: MenuBarStat) -> Double? {
        switch stat {
        case .cpu: cpu
        case .gpu: gpu
        case .memory: memory
        case .disk: disk
        }
    }

    public func text(_ stat: MenuBarStat) -> String {
        guard let value = value(stat), value.isFinite else { return "–" }
        return DisplayFormat.percent(min(100, max(0, value)))
    }
}

public enum GPUUsage {
    /// How busy the GPU is, from the graphics driver's own statistics. The busiest GPU wins on Macs with more than one.
    public static func read() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var busiest: Double?
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let stats = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any],
               let usage = (stats["Device Utilization %"] as? NSNumber)?.doubleValue {
                busiest = max(busiest ?? 0, usage)
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return busiest
    }
}

public enum DiskUsage {
    /// How full the startup disk is, counting space macOS can free on its own as available, like Finder does.
    public static func read() -> Double? {
        let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        guard let total = values?.volumeTotalCapacity, total > 0,
              let available = values?.volumeAvailableCapacityForImportantUsage else { return nil }
        return percentUsed(total: Int64(total), available: available)
    }

    static func percentUsed(total: Int64, available: Int64) -> Double {
        100 * Double(max(0, total - available)) / Double(total)
    }
}
