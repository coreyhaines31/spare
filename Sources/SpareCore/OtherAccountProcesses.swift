import Foundation

/// macOS processes that run outside your account, such as WindowServer and mds_stores.
/// macOS lets an app measure only its own user's processes, but /bin/ps is installed setuid root and can list them all.
public enum OtherAccountProcesses {
    public struct Row: Equatable {
        public let pid: Int32
        public let parent: Int32
        public let residentBytes: UInt64
        public let cpuSeconds: Double
        public let path: String
    }

    /// Runs ps once. Returns nothing if it can't, so readings fall back to your own processes.
    public static func read() -> [Row] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,ppid=,rss=,time=,comm="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return [] }
        return parse(String(decoding: data, as: UTF8.self))
    }

    /// Parses `ps -axo pid=,ppid=,rss=,time=,comm=`. The path is last, so it may contain spaces.
    public static func parse(_ output: String) -> [Row] {
        output.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
            guard fields.count == 5, let pid = Int32(fields[0]), let parent = Int32(fields[1]),
                  let resident = UInt64(fields[2]), let cpu = cpuSeconds(String(fields[3])) else { return nil }
            return Row(pid: pid, parent: parent, residentBytes: resident * 1024, cpuSeconds: cpu,
                       path: String(fields[4]).trimmingCharacters(in: .whitespaces))
        }
    }

    /// ps prints CPU time as `[[days-]hours:]minutes:seconds`, and minutes may pass 60.
    public static func cpuSeconds(_ text: String) -> Double? {
        let dayParts = text.split(separator: "-")
        guard (1...2).contains(dayParts.count) else { return nil }
        let days = dayParts.count == 2 ? Double(dayParts[0]) : 0
        let units = dayParts.last!.split(separator: ":").map { Double($0) }
        guard let days, (2...3).contains(units.count), units.allSatisfy({ $0 != nil }) else { return nil }
        let values = units.compactMap { $0 }
        let seconds = values.reversed().enumerated().reduce(0.0) { total, item in total + item.element * pow(60, Double(item.offset)) }
        return days * 86_400 + seconds
    }
}
