import SwiftUI
import SpareCore

/// Breaks a multi-process app into its helpers by role, and lets people end one tab or extension process.
struct AppHelpersSection: View {
    let workload: Workload
    @ObservedObject var monitor: Monitor
    @State private var showAll = false
    @State private var confirming: ProcessIdentity?
    private let collapsedCount = 8

    private var browser: Bool { ProcessClassifier.isBrowser(workload.name) }
    private var helpers: [(process: ProcessRecord, role: HelperRole)] {
        workload.processes.sorted { $0.memory > $1.memory }.map { process in
            (process, HelperRole.classify(name: process.name, arguments: ArgumentCache.arguments(for: process.identity),
                                          isMain: process.identity == workload.appIdentity))
        }
    }

    var body: some View {
        let all = helpers
        VStack(alignment: .leading, spacing: 10) {
            Text("Inside \(workload.name)").font(.headline)
            Text(summary(all)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if browser && ["chrome", "brave"].contains(where: workload.name.lowercased().contains) {
                Label("To match a process to a tab, open \(workload.name)’s Task Manager: Window → Task Manager. It shows each tab’s memory.",
                      systemImage: "lightbulb").font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 2) {
                ForEach(showAll ? all : Array(all.prefix(collapsedCount)), id: \.process.identity) { helper in
                    row(helper.process, helper.role)
                }
            }
            if all.count > collapsedCount {
                Button(showAll ? "Show fewer" : "Show all \(all.count) processes") { showAll.toggle() }.buttonStyle(.link)
            }
        }
    }

    private func row(_ process: ProcessRecord, _ role: HelperRole) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(role == .main ? "\(workload.name) itself" : role.label(browser: browser)).font(.callout.weight(.medium))
                    Text(verbatim: "PID \(process.identity.pid)").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(DisplayFormat.memory(process.memory)).font(.callout).monospacedDigit()
                    Text("\(DisplayFormat.percent(process.cpu)) CPU").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                }
                if role.canEnd && confirming != process.identity {
                    Button("End…") { confirming = process.identity }
                        .controlSize(.small).help("Review ending this \(role.label(browser: browser).lowercased()) process")
                }
            }
            if confirming == process.identity {
                VStack(alignment: .leading, spacing: 8) {
                    Text(role.consequence(browser: browser)).font(.caption).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Cancel") { confirming = nil }.keyboardShortcut(.cancelAction)
                        Spacer()
                        Button("End process", role: .destructive) {
                            monitor.endHelper(process, role: role, in: workload)
                            confirming = nil
                        }.buttonStyle(.borderedProminent).tint(.red).controlSize(.small)
                    }
                }.padding(10).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }
        }.padding(.vertical, 6).padding(.horizontal, 8)
    }

    private func summary(_ all: [(process: ProcessRecord, role: HelperRole)]) -> String {
        var totals: [String: (count: Int, memory: UInt64)] = [:]
        for helper in all {
            totals[helper.role.pluralLabel(browser: browser), default: (0, 0)].count += 1
            totals[helper.role.pluralLabel(browser: browser), default: (0, 0)].memory += helper.process.memory
        }
        return totals.sorted { $0.value.memory > $1.value.memory }
            .map { "\($0.key): \($0.value.count) · \(DisplayFormat.memory($0.value.memory))" }
            .joined(separator: "\n")
    }
}

/// Launch arguments don't change for a process's lifetime, so each is read once.
private enum ArgumentCache {
    private static var cache: [ProcessIdentity: [String]] = [:]

    static func arguments(for identity: ProcessIdentity) -> [String] {
        if let cached = cache[identity] { return cached }
        if cache.count > 4000 { cache.removeAll() }
        let arguments = ProcessArguments.read(pid: identity.pid)
        cache[identity] = arguments
        return arguments
    }
}
