import SwiftUI
import SpareCore

/// Breaks a multi-process app into its helpers by role, and lets people end one tab or extension process.
struct AppHelpersSection: View {
    let workload: Workload
    @ObservedObject var monitor: Monitor
    @State private var showAll = false
    @State private var confirming: ProcessIdentity?
    @State private var waitingForPermission = false
    @State private var menuUnavailable = false
    @State private var memorySaver = ChromeMemorySaver.unknown
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
            if workload.name == "Google Chrome", let pid = workload.appIdentity?.pid {
                chromeTools(pid: pid)
            } else if browser && workload.name.lowercased().contains("brave") {
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

    private func chromeTools(pid: Int32) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { openTaskManager(pid: pid) } label: { Label("Open Chrome’s Task Manager", systemImage: "list.bullet.rectangle") }
            Text("It names the tab behind each process. Click the Memory footprint column to sort, then End process.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if waitingForPermission {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Turn on Spare in Accessibility settings. Chrome’s Task Manager opens as soon as you do. Spare only uses this permission to choose that menu item.")
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Open Accessibility Settings") { ChromeShortcuts.openAccessibilitySettings() }
                        Button("Cancel") { waitingForPermission = false }.buttonStyle(.link)
                    }.controlSize(.small)
                }
                .padding(10).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .task(id: waitingForPermission) { await waitForPermission(pid: pid) }
            } else if menuUnavailable {
                Text("Couldn’t reach that menu. In Chrome, choose Window → Task Manager.")
                    .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            if let tip = memorySaverTip, let appPath = workload.appPath {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "leaf.arrow.triangle.circlepath").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tip).font(.caption).fixedSize(horizontal: false, vertical: true)
                        Button("Open Performance settings") {
                            ChromeShortcuts.openPerformanceSettings(appURL: URL(fileURLWithPath: appPath))
                        }.buttonStyle(.link).font(.caption)
                    }
                }
            }
        }
        .onAppear { memorySaver = ChromeMemorySaver.read() }
    }

    private func openTaskManager(pid: Int32) {
        switch ChromeShortcuts.openTaskManager(pid: pid) {
        case .opened: waitingForPermission = false; menuUnavailable = false
        case .needsPermission:
            waitingForPermission = true
        case .notFound: waitingForPermission = false; menuUnavailable = true
        }
    }

    /// Checks for the permission for up to two minutes, then opens the Task Manager without another click.
    private func waitForPermission(pid: Int32) async {
        for _ in 0..<120 {
            try? await Task.sleep(for: .seconds(1))
            guard waitingForPermission, !Task.isCancelled else { return }
            if ChromeShortcuts.isTrusted {
                openTaskManager(pid: pid)
                return
            }
        }
    }

    private var memorySaverTip: String? {
        switch memorySaver {
        case .off: return "Memory Saver is off. Turning it on lets Chrome unload tabs you haven’t used recently."
        case .on(maximum: false): return "Memory Saver is on. Setting it to Maximum unloads inactive tabs sooner."
        default: return nil
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
