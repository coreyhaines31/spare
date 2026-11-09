import Foundation

public struct Health {
    public let title: String
    public let message: String
    public let level: Int
    /// True only when nothing is strained, which is the one state that earns a green check.
    public let isCalm: Bool
    public init(samples: [SystemSample], ready: Bool) {
        isCalm = ready && samples.last.map { $0.pressure == .normal && $0.cpu <= Self.busyCPU } == true
        guard ready, let latest = samples.last else {
            title = "Getting a feel for your Mac"
            message = "The first readings will be ready in a few seconds."
            level = 0
            return
        }
        if latest.pressure == .critical {
            title = "Your Mac needs breathing room"
            message = "Memory pressure is high. Save your work, then review an app or project you can close."
            level = 2
        } else if latest.pressure == .warning {
            title = "Memory is getting stretched"
            message = "macOS is working harder to make room. Closing something you’re finished with can help."
            level = 1
        } else if Self.busySpan(samples) >= 18 {
            title = "Your Mac has a lot to do"
            message = "Processing power has been busy for a while. The list below shows what’s working hardest."
            level = 1
        } else if latest.cpu > Self.busyCPU {
            title = "Busy right now"
            message = "Processing power is nearly all in use at the moment. Short bursts are normal."
            level = 0
        } else if latest.pressure == .unknown {
            title = "Watching your Mac"
            message = "CPU readings are available. macOS memory pressure is unavailable right now."
            level = 0
        } else {
            title = "Room to work"
            message = "Processing power and memory both have headroom. Lots of used memory is normal."
            level = 0
        }
    }

    static let busyCPU = 85.0

    /// How many seconds the CPU has stayed busy without a break, up to the latest reading. Measured in time
    /// rather than readings, because a maxed-out Mac delays Spare's own readings too.
    static func busySpan(_ samples: [SystemSample]) -> TimeInterval {
        guard let latest = samples.last else { return 0 }
        var start = latest.date
        var previous = latest.date
        for sample in samples.reversed() {
            guard sample.cpu > busyCPU, previous.timeIntervalSince(sample.date) <= 30 else { break }
            start = sample.date
            previous = sample.date
        }
        return latest.date.timeIntervalSince(start)
    }
}

public enum PressureAlert {
    public static func isSustained(_ samples: [SystemSample]) -> Bool {
        let recent = Array(samples.suffix(20))
        guard recent.count == 20, let first = recent.first, let last = recent.last,
              last.date.timeIntervalSince(first.date) >= 50,
              last.date.timeIntervalSince(first.date) <= 75 else { return false }
        guard zip(recent.dropFirst(), recent).allSatisfy({
            let gap = $0.date.timeIntervalSince($1.date)
            return gap > 0 && gap <= 6
        }) else { return false }
        return recent.allSatisfy { $0.pressure == .warning || $0.pressure == .critical } ||
            recent.allSatisfy { $0.cpu > 85 }
    }
}
