import SwiftUI
import SpareCore
import PanelKit

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
    @Environment(\.panelTheme) private var theme

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
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("Inside \(workload.name)")
            PanelNote(summary(all)).padding(.bottom, 8)
            VStack(alignment: .leading, spacing: 8) {
                if workload.name == "Google Chrome", let pid = workload.appIdentity?.pid {
                    chromeTools(pid: pid)
                } else if browser && workload.name.lowercased().contains("brave") {
                    Label("To match a process to a tab, open \(workload.name)’s Task Manager: Window → Task Manager. It shows each tab’s memory.",
                          systemImage: "lightbulb").font(PanelFont.body(11.5)).foregroundStyle(theme.sub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                sessionActions(all.filter { $0.role == .session }.map(\.process), origins: origins)
            }.padding(.horizontal, 14)
            Tabs(HelperSort.allCases.map { PanelChoice($0, $0.rawValue) }, selection: $sort)
                .padding(.top, 8).accessibilityLabel("Sort by")
            VStack(spacing: 0) {
                ForEach(showAll ? all : Array(all.prefix(collapsedCount)), id: \.process.identity) { helper in
                    row(helper.process, helper.role, origin: origins[helper.process.identity])
                }
            }
            if all.count > collapsedCount {
                Button(showAll ? "Show fewer" : "Show all \(all.count) processes") { showAll.toggle() }.buttonStyle(.panelQuietLink)
                    .padding(.horizontal, 14).padding(.vertical, 6)
            }
        }.padding(.bottom, 6)
    }

    private func chromeTools(pid: Int32) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { openTaskManager(pid: pid) } label: { Label("Open Chrome’s Task Manager", systemImage: "list.bullet.rectangle") }
                .buttonStyle(.panelSecondary)
            Text("It names the tab behind each process. Click the Memory footprint column to sort, then End process.")
                .font(PanelFont.body(11.5)).foregroundStyle(theme.sub).fixedSize(horizontal: false, vertical: true)
            if monitor.awaitingAccessibility {
                Recess {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Turn on Spare in Accessibility settings. Chrome’s Task Manager opens as soon as you do. Spare only uses this permission to choose that menu item.")
                            .font(PanelFont.body(11.5)).fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button("Open Accessibility Settings") { ChromeShortcuts.openAccessibilitySettings() }.buttonStyle(.panelCompact)
                            Button("Cancel") { monitor.cancelAccessibilityWait() }.buttonStyle(.panelQuietLink)
                        }
                    }
                }
            } else if menuUnavailable {
                Text("Couldn’t reach that menu. In Chrome, choose Window → Task Manager.")
                    .font(PanelFont.body(11.5)).foregroundStyle(theme.caution).fixedSize(horizontal: false, vertical: true)
            }
            if let tip = memorySaverTip, let appPath = workload.appPath {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "leaf.arrow.triangle.circlepath").foregroundStyle(theme.sub)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tip).font(PanelFont.body(11.5)).fixedSize(horizontal: false, vertical: true)
                        Button("Open Performance settings") {
                            ChromeShortcuts.openPerformanceSettings(appURL: URL(fileURLWithPath: appPath))
                        }.buttonStyle(.panelQuietLink)
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
                ConfirmBox(message: "Close \(closing.count) separate session\(closing.count == 1 ? "" : "s")? \(HelperRole.session.consequence(browser: browser))",
                           action: "Close sessions", cancel: { closingSessions = nil }, confirm: {
                    monitor.endSessions(closing, in: workload)
                    closingSessions = nil
                })
            } else {
                HStack {
                    if !leftovers.isEmpty {
                        Button("Close \(leftovers.count) background session\(leftovers.count == 1 ? "" : "s")…") { closingSessions = leftovers }
                    }
                    if leftovers.count != sessions.count {
                        Button("Close all \(sessions.count) sessions…") { closingSessions = sessions }
                    }
                }.buttonStyle(.panelCompact)
            }
        }
    }

    private func row(_ process: ProcessRecord, _ role: HelperRole, origin: SessionOrigin?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(role == .main ? "\(workload.name) itself" : role.label(browser: browser)).font(PanelFont.body(12.5, .semibold))
                    if let origin {
                        Text(origin.description).font(PanelFont.body(11)).lineLimit(1)
                            .foregroundStyle(origin.isUnattended ? theme.caution : theme.sub)
                    } else {
                        Text(verbatim: "PID \(process.identity.pid)").font(PanelFont.body(11)).foregroundStyle(theme.sub)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(DisplayFormat.memory(process.memory)).font(PanelFont.body(12.5)).monospacedDigit()
                    Text("\(DisplayFormat.percent(process.cpu)) CPU").font(PanelFont.body(11)).foregroundStyle(theme.sub).monospacedDigit()
                }
                if role.canEnd && confirming != process.identity {
                    Button("End…") { confirming = process.identity }.buttonStyle(.panelCompact)
                        .help("Review ending this \(role.label(browser: browser).lowercased()) process")
                } else if let reason = role.lockedReason {
                    Button { explaining = explaining == process.identity ? nil : process.identity } label: {
                        Image(systemName: "lock").foregroundStyle(theme.sub)
                    }.buttonStyle(.plain).help(reason).accessibilityLabel("Why this can’t be ended")
                }
            }
            if explaining == process.identity, let reason = role.lockedReason {
                Text(reason).font(PanelFont.body(11.5)).foregroundStyle(theme.sub).fixedSize(horizontal: false, vertical: true)
            }
            if confirming == process.identity {
                ConfirmBox(message: role.consequence(browser: browser), action: "End process", cancel: { confirming = nil }, confirm: {
                    monitor.endHelper(process, role: role, in: workload)
                    confirming = nil
                })
            }
        }.padding(.vertical, 6).padding(.horizontal, 14)
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
