import Foundation

public enum RecapCSV {
    public static func make(_ report: RecapReport) -> String {
        var rows = [["record_type", "hour_start", "hour_end", "recorded_seconds", "average_cpu_percent",
                     "cpu_above_85_seconds", "elevated_pressure_seconds", "known_pressure_seconds",
                     "workload_name", "workload_kind", "seen_seconds", "average_memory_bytes", "peak_memory_bytes"]]
        let iso = ISO8601DateFormatter()
        for bucket in report.buckets.sorted(by: { $0.start < $1.start }) {
            let totals = bucket.totals
            guard totals.observed > 0 else { continue }
            let base = [iso.string(from: bucket.start), iso.string(from: bucket.end), number(totals.observed)]
            rows.append(["system"] + base + [number(totals.averageCPU), number(totals.busySeconds),
                number(totals.pressureSeconds), number(totals.knownPressureSeconds), "", "", "", "", ""])
            for item in bucket.workloads.values.sorted(by: { $0.id < $1.id }) {
                rows.append(["workload"] + base + [number(item.cpuSeconds / totals.observed), "", "", "",
                    item.name, item.kind.label, number(item.observed), number(item.memoryByteSeconds / totals.observed), String(item.peakMemory)])
            }
        }
        return rows.map { $0.map(escape).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }
    private static func number(_ value: Double) -> String {
        String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
    private static func escape(_ value: String) -> String {
        let first = value.trimmingCharacters(in: .whitespacesAndNewlines).first
        let formula = first.map { "=+-@".contains($0) } ?? false
        let safe = formula || value.hasPrefix("\t") || value.hasPrefix("\r") ? "'" + value : value
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
