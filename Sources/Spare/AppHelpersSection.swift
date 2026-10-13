import SwiftUI
import SpareCore

/// Breaks a multi-process app into its helpers by role, and lets people end one tab or extension process.
struct AppHelpersSection: View {
    let workload: Workload
    @ObservedObject var monitor: Monitor
    @State private var showAll = false
    @State private var confirming: ProcessIdentity?
    @State private var explaining: ProcessIdentity?
    @State private var sort = HelperSort.memory
    @State private var closingSessions: [ProcessRecord]?
    @State private var menuUnavailable = false
    @State private var memorySaver = ChromeMemorySaver.unknown
    private let collapsedCount = 8

    private var browser: Bool { ProcessClassifier.isBrowser(workload.name) }
    private var helpers: [(process: ProcessRecord, role: HelperRole)] {
        let mainPath = workload.processes.first { $0.identity == workload.appIdentity }?.path ?? ""
        let classified = workload.processes.map { process in
            (process: process, role: HelperRole.classify(name: process.name, arguments: ProcessArguments.cached(for: process.identity),
                                                         isMain: process.identity == workload.appIdentity,
                                                         path: process.path, mainPath: mainPath))
        }
        switch sort {
        case .memory: return classified.sorted { $0.process.memory > $1.process.memory }
        case .cpu: return classified.sorted { ($0.process.cpu, $0.process.memory) > ($1.process.cpu, $1.process.memory) }
        case .type:
            return classified.sorted {
                let left = $0.role.pluralLabel(browser: browser), right = $1.role.pluralLabel(browser: browser)
                return left == right ? $0.process.memory > $1.process.memory : left < right
            }
        }
    }

    private enum HelperSort: String, CaseIterable, Identifiable {
        case memory = "Memory", cpu = "CPU", type = "Type"
        var id: Self { self }
    }

    var body: some View {
        let all = helpers
        let origins = monitor.origins(of: all.filter { $0.role == .session }.map(\.process))
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
            sessionActions(all.filter { $0.role == .session }.map(\.process), origins: origins)
            Picker("Sort by", selection: $sort) {
                ForEach(HelperSort.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).controlSize(.small)
            VStack(spacing: 2) {
                ForEach(showAll ? all : Array(all.prefix(collapsedCount)), id: \.process.identity) { helper in
                    row(helper.process, helper.role, origin: origins[helper.process.identity])
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
            if monitor.awaitingAccessibility {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Turn on Spare in Accessibility settings. Chrome’s Task Manager opens as soon as you do. Spare only uses this permission to choose that menu item.")
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Open Accessibility Settings") { ChromeShortcuts.openAccessibilitySettings() }
                        Button("Cancel") { monitor.cancelAccessibilityWait() }.buttonStyle(.link)
                    }.controlSize(.small)
                }
                .padding(10).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
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
        menuUnavailable = monitor.openChromeTaskManager(pid: pid) == .notFound
    }

    private var memorySaverTip: String? {
        switch memorySaver {
        case .off: return "Memory Saver is off. Turning it on lets Chrome unload tabs you haven’t used recently."
        case .on(maximum: false): return "Memory Saver is on. Setting it to Maximum unloads inactive tabs sooner."
        default: return nil
        }
    }

    @ViewBuilder private func sessionActions(_ sessions: [ProcessRecord], origins: [ProcessIdentity: SessionOrigin]) -> some View {
        if sessions.count > 1 {
            let leftovers = browser ? sessions.filter { origins[$0.identity]?.isUnattended == true } : []
            if let closing = closingSessions {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Close \(closing.count) separate session\(closing.count == 1 ? "" : "s")? \(HelperRole.session.consequence(browser: browser))")
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Cancel") { closingSessions = nil }.keyboardShortcut(.cancelAction)
                        Spacer()
                        Button("Close sessions", role: .destructive) {
                            monitor.endSessions(closing, in: workload)
                            closingSessions = nil
                        }.buttonStyle(.borderedProminent).tint(.red).controlSize(.small)
                    }
                }.padding(10).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            } else {
                HStack {
                    if !leftovers.isEmpty {
                        Button("Close \(leftovers.count) background session\(leftovers.count == 1 ? "" : "s")…") { closingSessions = leftovers }
                    }
                    if leftovers.count != sessions.count {
                        Button("Close all \(sessions.count) sessions…") { closingSessions = sessions }
                    }
                }.controlSize(.small)
            }
        }
    }

    private func row(_ process: ProcessRecord, _ role: HelperRole, origin: SessionOrigin?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(role == .main ? "\(workload.name) itself" : role.label(browser: browser)).font(.callout.weight(.medium))
                    if let origin {
                        Text(origin.description).font(.caption2).lineLimit(1)
                            .foregroundStyle(origin.isUnattended ? Color.orange : Color.secondary)
                    } else {
                        Text(verbatim: "PID \(process.identity.pid)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(DisplayFormat.memory(process.memory)).font(.callout).monospacedDigit()
                    Text("\(DisplayFormat.percent(process.cpu)) CPU").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                }
                if role.canEnd && confirming != process.identity {
                    Button("End…") { confirming = process.identity }
                        .controlSize(.small).help("Review ending this \(role.label(browser: browser).lowercased()) process")
                } else if let reason = role.lockedReason {
                    Button { explaining = explaining == process.identity ? nil : process.identity } label: {
                        Image(systemName: "lock").foregroundStyle(.secondary)
                    }.buttonStyle(.borderless).help(reason).accessibilityLabel("Why this can’t be ended")
                }
            }
            if explaining == process.identity, let reason = role.lockedReason {
                Text(reason).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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
