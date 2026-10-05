import Foundation

public struct Health {
    public let title: String
    public let message: String
    public let level: Int
    public init(samples: [SystemSample], ready: Bool) {
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
        } else if samples.filter({ latest.date.timeIntervalSince($0.date) <= 24 }).count >= 7,
                  samples.suffix(7).allSatisfy({ $0.cpu > 85 }) {
            title = "Your Mac has a lot to do"
            message = "Processing power has been busy for a while. Sort by CPU to see what’s working hardest."
            level = 1
        } else if latest.pressure == .unknown {
            title = "Watching your Mac"
            message = "CPU readings are available. macOS memory pressure is unavailable right now."
            level = 0
        } else {
            title = "Room to work"
            message = "Memory pressure looks healthy. A busy moment or lots of used memory is normal."
            level = 0
        }
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
