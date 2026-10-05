import Foundation
import Darwin

public final class RecapStore {
    private struct Archive: Codable {
        var version = 2
        var buckets: [RecapBucket]
    }
    public let history: RecapHistory
    public private(set) var error: String?
    private let url: URL
    private var blocked = false
    private var lastSave = Date.distantPast
    public init(url: URL, now: Date = Date()) {
        self.url = url
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                var archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: url))
                guard archive.version == 1 || archive.version == 2 else { throw CocoaError(.fileReadCorruptFile) }
                if archive.version == 1 {
                    var timebase = mach_timebase_info_data_t()
                    guard mach_timebase_info(&timebase) == KERN_SUCCESS, timebase.denom > 0 else { throw CocoaError(.fileReadUnknown) }
                    let scale = Double(timebase.numer) / Double(timebase.denom)
                    for index in archive.buckets.indices {
                        for id in Array(archive.buckets[index].workloads.keys) {
                            archive.buckets[index].workloads[id]?.cpuSeconds *= scale
                        }
                    }
                }
                history = RecapHistory(buckets: archive.buckets)
                history.prune(at: now)
            } else { history = RecapHistory() }
        } catch {
            history = RecapHistory()
            blocked = true
            self.error = "Saved recap history couldn’t be read. Recording is paused to protect it. Clear saved history to start again."
        }
    }
    public func record(_ sample: SystemSample?, workloads: [Workload], ready: Bool, enabled: Bool, now: Date = Date()) {
        guard !blocked else { return }
        if let sample, enabled { history.record(sample, workloads: workloads, ready: ready) }
        else { history.pause(); history.prune(at: now) }
        if now.timeIntervalSince(lastSave) >= 60 { save(at: now) }
    }
    public func save(at date: Date = Date()) {
        guard !blocked else { return }
        lastSave = date
        do {
            history.prune(at: date)
            try write(history.buckets)
            lastSave = date
            error = nil
        } catch {
            self.error = "Recap history couldn’t be saved. Current readings are still available; Spare will retry."
        }
    }
    @discardableResult public func clear() -> Bool {
        do {
            try write([])
            history.clear()
            blocked = false
            error = nil
            lastSave = .distantPast
            return true
        } catch {
            self.error = "Saved history couldn’t be cleared. Your existing history has been kept."
            return false
        }
    }
    private func write(_ buckets: [RecapBucket]) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        let data = try JSONEncoder().encode(Archive(buckets: buckets))
        try data.write(to: url, options: [.atomic])
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
