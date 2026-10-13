import Foundation
import CSpare

public struct Snapshot {
    public let system: SystemSample
    public let processes: [ProcessRecord]
    public let ready: Bool
}

public final class Sampler {
    private var previous: [ProcessIdentity: UInt64] = [:]
    private var ticks: [UInt32]?
    private var time: TimeInterval?
    private let cores = Double(ProcessInfo.processInfo.activeProcessorCount)

    public init() {}

    public func reset() { previous = [:]; ticks = nil; time = nil }

    public func sample() -> Snapshot? {
        var raw = SpareSystem()
        guard spare_system(&raw) else { return nil }
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = time.map { now - $0 } ?? 0
        let ready = elapsed > 0 && elapsed < 15
        let currentTicks = [raw.cpu.0, raw.cpu.1, raw.cpu.2, raw.cpu.3]
        var cpu = 0.0
        if let ticks, ready {
            let delta = zip(currentTicks, ticks).map { UInt64($0 &- $1) }
            let total = delta.reduce(0, +)
            if total > 0 { cpu = 100 * Double(total - delta[2]) / Double(total) }
        }
        ticks = currentTicks
        time = now
        var pids = [Int32](repeating: 0, count: 65536)
        let count = Int(spare_pids(&pids, Int32(pids.count)))
        var processes: [ProcessRecord] = []
        var counters: [ProcessIdentity: UInt64] = [:]
        for pid in pids.prefix(max(0, count)) {
            var process = SpareProcess()
            guard spare_process(pid, &process, true) else { continue }
            let identity = ProcessIdentity(pid: pid, started: process.started)
            var usage = 0.0
            if ready, let old = previous[identity], process.cpu_ns >= old {
                usage = min(100, Double(process.cpu_ns - old) / (elapsed * 1_000_000_000 * cores) * 100)
            }
            counters[identity] = process.cpu_ns
            var record = ProcessRecord(pid: pid, started: process.started, parent: process.parent_pid,
                name: string(&process.name), path: string(&process.path), directory: string(&process.directory),
                memory: process.memory, cpu: usage)
            if ProcessClassifier.developerKind(record) != nil {
                var ports = [UInt16](repeating: 0, count: 16)
                let portCount = spare_ports(pid, &ports, 16)
                record.ports = Array(ports.prefix(max(0, Int(portCount))))
            }
            processes.append(record)
        }
        // Shipped system processes outside your account, measured the same way but with resident memory as the estimate.
        let readable = Set(processes.map(\.identity.pid))
        for row in OtherAccountProcesses.read() where !readable.contains(row.pid) && SystemProcessCatalog.isShipped(row.path) {
            var started: UInt64 = 0
            guard spare_start_time(row.pid, &started) else { continue }
            let identity = ProcessIdentity(pid: row.pid, started: started)
            let cpuNanoseconds = UInt64(row.cpuSeconds * 1_000_000_000)
            var usage = 0.0
            if ready, let old = previous[identity], cpuNanoseconds >= old {
                usage = min(100, Double(cpuNanoseconds - old) / (elapsed * 1_000_000_000 * cores) * 100)
            }
            let record = ProcessRecord(pid: row.pid, started: started, parent: row.parent,
                                       name: URL(fileURLWithPath: row.path).lastPathComponent, path: row.path,
                                       memory: row.residentBytes, cpu: usage)
            // A runtime like /usr/bin/python3 running as root isn't your project, and Spare couldn't stop it.
            guard ProcessClassifier.developerKind(record) == nil else { continue }
            counters[identity] = cpuNanoseconds
            processes.append(record)
        }
        previous = counters
        return Snapshot(system: SystemSample(cpu: cpu, memory: raw.used, physical: raw.physical,
            compressed: raw.compressed, swap: raw.swap, pressure: MemoryPressure(level: raw.pressure)),
            processes: processes, ready: ready)
    }

    private func string<T>(_ value: inout T) -> String {
        withUnsafePointer(to: &value) {
            $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<T>.size) { String(cString: $0) }
        }
    }
}
