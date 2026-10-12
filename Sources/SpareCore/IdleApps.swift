import Foundation

/// Remembers when each app was last in front, so apps left open but unused can be suggested for quitting.
public final class AppActivityLog {
    private let defaults: UserDefaults
    private let key = "appLastActive"
    private let seenKey = "appActivityWatchedAt"
    private let started: Date
    /// Saved activations are trusted only if Spare was watching right up to this launch.
    private let trustedSince: Date
    private var lastActive: [String: Date]
    private var lastMarked = Date.distantPast

    public init(defaults: UserDefaults = .standard, now: Date = Date()) {
        self.defaults = defaults
        started = now
        let stored = defaults.dictionary(forKey: key) as? [String: Double] ?? [:]
        lastActive = stored.mapValues { Date(timeIntervalSince1970: $0) }
        let watched = defaults.object(forKey: seenKey) as? Double
        trustedSince = watched.map { now.timeIntervalSince1970 - $0 <= 600 } == true ? .distantPast : now
    }

    /// Notes that Spare is watching, at most once a minute, so a later launch can tell whether it missed time.
    public func markWatching(at date: Date = Date()) {
        guard date.timeIntervalSince(lastMarked) >= 60 else { return }
        lastMarked = date
        defaults.set(date.timeIntervalSince1970, forKey: seenKey)
    }

    public func recordActivation(appPath: String, at date: Date = Date()) {
        lastActive[appPath] = date
        defaults.set(lastActive.mapValues(\.timeIntervalSince1970), forKey: key)
    }

    /// How long an app has gone unused. Time Spare didn't watch never counts as idle, so the estimate errs short.
    public func idleTime(appPath: String, launched: Date?, now: Date = Date()) -> TimeInterval {
        let known = lastActive[appPath].map { max($0, trustedSince) } ?? started
        let since = max(known, launched ?? known)
        return max(0, now.timeIntervalSince(since))
    }
}

public struct IdleApp {
    public let workload: Workload
    public let idle: TimeInterval

    public init(workload: Workload, idle: TimeInterval) {
        self.workload = workload
        self.idle = idle
    }
}

public enum IdleApps {
    public static let threshold: TimeInterval = 2 * 3600
    public static let minimumMemory: UInt64 = 300 * 1024 * 1024

    /// Apps that can be quit, have gone unused past the threshold, and use enough memory to matter, largest first.
    public static func find(_ workloads: [Workload], idle: (Workload) -> TimeInterval?) -> [IdleApp] {
        workloads.compactMap { workload in
            guard workload.kind == .application, workload.canStop, workload.memory >= minimumMemory,
                  let time = idle(workload), time >= threshold else { return nil }
            return IdleApp(workload: workload, idle: time)
        }.sorted { $0.workload.memory > $1.workload.memory }
    }

    public static func describe(_ time: TimeInterval) -> String {
        let hours = Int(time / 3600)
        if hours >= 48 { return "not used in \(hours / 24) days" }
        if hours >= 1 { return "not used in \(hours)h" }
        return "not used in \(Int(time / 60))m"
    }
}
