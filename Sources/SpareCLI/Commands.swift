import AppKit
import SpareCore

enum Commands {
    static func status() -> Never {
        let reading = Reading.take()
        let status = StatusSummary(sample: reading.snapshot.system, ready: reading.snapshot.ready)
        if Output.json {
            Output.print(status)
        } else {
            print(status.title)
            print("CPU \(DisplayFormat.percent(status.cpuPercent)) in use (\(DisplayFormat.percent(status.cpuAvailablePercent)) available) · "
                + "Memory pressure \(pressureLabel(status.memoryPressure)) · \(status.memoryUsed) of \(status.memoryTotal) in use")
            if status.exitCode != 0 { print(status.message + " Run `spare list` to see what’s using the most.") }
        }
        exit(status.exitCode)
    }

    static func list(_ options: Options) {
        let reading = Reading.take()
        let visible = reading.workloads.filter { $0.kind != .background && options.filter.includes($0) }.sorted {
            options.sortCPU ? ($0.cpu, $0.memory) > ($1.cpu, $1.memory) : $0.memory > $1.memory
        }
        let shown = options.limit > 0 ? Array(visible.prefix(options.limit)) : visible
        let summaries = shown.map { WorkloadSummary($0, command: reading.command(for: $0)) }
        if Output.json { return Output.print(summaries) }
        guard !summaries.isEmpty else { return print("Nothing matching is running.") }
        let rows = [["NAME", "KIND", "MEMORY", "CPU", "DETAILS"]] + summaries.map { item in
            [item.name, kindLabel(item.kind), item.memory, DisplayFormat.percent(item.cpuPercent), detailText(item)]
        }
        print(TextTable.render(rows, rightAligned: [2, 3], maxWidth: [0: 34]))
        if visible.count > shown.count { print("\n\(visible.count - shown.count) more. Use --limit 0 to show everything.") }
    }

    private struct Helper: Codable {
        var pid: Int32
        var name: String
        var role: String?
        var memoryBytes: UInt64
        var memory: String
        var cpuPercent: Double
        var origin: String?
    }

    private struct Group: Codable {
        var role: String
        var count: Int
        var memoryBytes: UInt64
        var memory: String
    }

    private struct Details: Codable {
        var workload: WorkloadSummary
        var explanation: String
        var ifClosed: String
        var urls: [String]
        var dockerMemoryLimitBytes: UInt64?
        var inside: [Group]
        var processes: [Helper]
        var quitCommand: String?
    }

    static func show(_ query: String) {
        let reading = Reading.take()
        let workload = reading.resolve(query)
        let browser = ProcessClassifier.isBrowser(workload.name)
        let mainPath = workload.processes.first { $0.identity == workload.appIdentity }?.path ?? ""
        let roles = Dictionary(workload.processes.map { process -> (ProcessIdentity, HelperRole) in
            (process.identity, HelperRole.classify(name: process.name, arguments: ProcessArguments.cached(for: process.identity),
                                                   isMain: process.identity == workload.appIdentity, path: process.path, mainPath: mainPath))
        }, uniquingKeysWith: { first, _ in first })
        let isApp = workload.kind == .application && workload.processes.count > 1
        let byRole = Dictionary(grouping: isApp ? workload.processes : []) { roles[$0.identity]?.pluralLabel(browser: browser) ?? "" }
        let inside: [Group] = byRole.map { role, processes in
            let memory = processes.reduce(UInt64(0)) { $0 + $1.memory }
            return Group(role: role, count: processes.count, memoryBytes: memory, memory: DisplayFormat.memory(memory))
        }.sorted { $0.memoryBytes > $1.memoryBytes }
        let helpers = workload.processes.sorted { $0.memory > $1.memory }.map { process in
            let role = roles[process.identity]
            return Helper(pid: process.identity.pid, name: process.name, role: isApp ? role?.label(browser: browser) : nil,
                          memoryBytes: process.memory, memory: DisplayFormat.memory(process.memory),
                          cpuPercent: (process.cpu * 10).rounded() / 10,
                          origin: role == .session ? reading.origin(of: process).description : nil)
        }
        let docker = DockerSettings.isDocker(workload) ? DockerSettings.memoryLimit(physical: reading.snapshot.system.physical) : nil
        let details = Details(workload: WorkloadSummary(workload, command: reading.command(for: workload)),
                              explanation: workload.explanation, ifClosed: workload.consequence,
                              urls: workload.webPorts.map { "http://localhost:\($0)" }, dockerMemoryLimitBytes: docker?.bytes,
                              inside: inside, processes: helpers,
                              quitCommand: workload.canStop ? "spare quit \(shellQuoted(workload.name))" : nil)
        if Output.json { return Output.print(details) }

        print(workload.name)
        print([kindLabel(details.workload.kind), details.workload.memory, "\(DisplayFormat.percent(details.workload.cpuPercent)) CPU",
               detailText(details.workload)].joined(separator: " · "))
        print("")
        print(workload.explanation)
        print("If you close it: \(workload.consequence)")
        if let path = workload.projectPath { print("Folder: \(DisplayFormat.homePath(path))") }
        if !details.urls.isEmpty { print("Open: " + details.urls.joined(separator: ", ")) }
        if let docker {
            print("Docker’s virtual machine can use up to \(DisplayFormat.memory(docker.bytes))\(docker.isDefault ? " (Docker’s default)" : ""). Lower it in Docker Desktop → Settings → Resources.")
        }
        if !inside.isEmpty { print("Inside: " + inside.map { "\($0.count) \($0.role.lowercased()) \($0.memory)" }.joined(separator: " · ")) }
        print("")
        let rows = [["PID", isApp ? "TYPE" : "PROCESS", "MEMORY", "CPU", ""]] + helpers.prefix(12).map {
            ["\($0.pid)", $0.role ?? $0.name, $0.memory, DisplayFormat.percent($0.cpuPercent), $0.origin ?? ""]
        }
        print(TextTable.render(rows, rightAligned: [0, 2, 3], maxWidth: [1: 28]))
        if helpers.count > 12 { print("…and \(helpers.count - 12) more. Use --json for all of them.") }
        print("")
        if let command = details.quitCommand {
            print("To close it: \(command)   (you approve it in Spare’s panel first)")
        } else {
            print("Spare doesn’t close this from here.")
        }
    }

    private struct IdleItem: Codable {
        var workload: WorkloadSummary
        var idleSeconds: Int
    }

    static func idle() {
        guard let spare = runningSpare else {
            Output.fail("Spare needs to be running to know when you last used each app. Start it with `spare open`, then try again later.")
        }
        let reading = Reading.take()
        let defaults = Bundle.main.bundleIdentifier == spareBundleID ? .standard : UserDefaults(suiteName: spareBundleID) ?? .standard
        let log = AppActivityLog(defaults: defaults, watchingSince: spare.launchDate ?? Date())
        let idle = IdleApps.find(reading.workloads) { workload in
            guard let path = workload.appPath, let pid = workload.appIdentity?.pid,
                  let app = NSRunningApplication(processIdentifier: pid), !app.isActive else { return nil }
            return log.idleTime(appPath: path, launched: app.launchDate)
        }
        let items = idle.map { IdleItem(workload: WorkloadSummary($0.workload, note: IdleApps.describe($0.idle)), idleSeconds: Int($0.idle)) }
        if Output.json { return Output.print(items) }
        guard !items.isEmpty else {
            return print("No apps over \(DisplayFormat.memory(IdleApps.minimumMemory)) have gone unused for 2+ hours since Spare opened.")
        }
        print(TextTable.render([["APP", "MEMORY", "IDLE"]] + items.map { [$0.workload.name, $0.workload.memory, $0.workload.note ?? ""] },
                               rightAligned: [1]))
        print("\nTo quit one: spare quit <name>   (you approve it in Spare’s panel first)")
    }

    private struct LeftoverItem: Codable {
        var app: String
        var pid: Int32
        var memoryBytes: UInt64
        var memory: String
        var origin: String
    }

    static func leftovers(_ options: Options) {
        let reading = Reading.take()
        let filter = options.positional.first
        let found = reading.leftovers.filter { filter == nil || $0.app.name.localizedCaseInsensitiveContains(filter ?? "") }
        if options.close {
            guard !found.isEmpty else { Output.fail("No leftover sessions right now, so there’s nothing to close.") }
            Requests.send(.init(action: .closeLeftovers, target: filter ?? "", requester: reading.requester), options: options)
        }
        let items = found.map {
            LeftoverItem(app: $0.app.name, pid: $0.process.identity.pid, memoryBytes: $0.memory,
                         memory: DisplayFormat.memory($0.memory), origin: $0.origin.description)
        }
        if Output.json { return Output.print(items) }
        guard !items.isEmpty else { return print("No leftover sessions right now.") }
        print(TextTable.render([["APP", "PID", "MEMORY", "WHY IT'S A LEFTOVER"]] + items.map { [$0.app, "\($0.pid)", $0.memory, $0.origin] },
                               rightAligned: [1, 2], maxWidth: [0: 30]))
        print("\nTo close them: spare leftovers --close   (you approve it in Spare’s panel first)")
    }

    private struct RecapItem: Codable {
        var name: String
        var kind: String
        var averageMemoryBytes: UInt64
        var averageMemory: String
        var averageCpuPercent: Double
    }

    private struct Recap: Codable {
        var period: String
        var start: Date
        var end: Date
        var recordedSeconds: Int
        var averageCpuPercent: Double
        var peakCpuPercent: Double
        var elevatedPressureSeconds: Int
        var elevatedPressurePercent: Double?
        var summary: String
        var topByMemory: [RecapItem]
        var topByCpu: [RecapItem]
    }

    static func recap(_ options: Options) {
        let periods: [String: RecapPeriod] = ["today": .today, "week": .week, "7d": .lastSevenDays]
        let name = options.positional.first ?? "today"
        guard let period = periods[name.lowercased()] else { Output.fail("Choose a period: today, week, or 7d.") }
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Spare/recaps.json")
        let store = RecapStore(url: url)
        if let error = store.error { Output.fail(error) }
        let report = store.history.report(period, at: Date())
        let observed = max(report.totals.observed, 1)
        let items = report.workloads.map {
            RecapItem(name: $0.name, kind: $0.kind.commandName, averageMemoryBytes: UInt64($0.memoryByteSeconds / observed),
                      averageMemory: DisplayFormat.memory(UInt64($0.memoryByteSeconds / observed)),
                      averageCpuPercent: (($0.cpuSeconds / observed) * 10).rounded() / 10)
        }
        let recap = Recap(period: period.rawValue, start: report.interval.start, end: report.interval.end,
                          recordedSeconds: Int(report.totals.observed), averageCpuPercent: (report.totals.averageCPU * 10).rounded() / 10,
                          peakCpuPercent: (report.totals.peakCPU * 10).rounded() / 10,
                          elevatedPressureSeconds: Int(report.totals.pressureSeconds),
                          elevatedPressurePercent: report.totals.pressurePercent.map { ($0 * 10).rounded() / 10 },
                          summary: report.summary,
                          topByMemory: Array(items.sorted { $0.averageMemoryBytes > $1.averageMemoryBytes }.prefix(5)),
                          topByCpu: Array(items.sorted { $0.averageCpuPercent > $1.averageCpuPercent }.prefix(5)))
        if Output.json { return Output.print(recap) }
        print("\(period.rawValue) · recorded \(RecapFormat.duration(report.totals.observed))")
        guard report.totals.observed >= 60 else { return print(report.summary) }
        print("Average CPU \(DisplayFormat.percent(recap.averageCpuPercent)) · peak \(DisplayFormat.percent(recap.peakCpuPercent))")
        print(report.summary)
        print("Most memory: " + recap.topByMemory.map { "\($0.name) \($0.averageMemory)" }.joined(separator: " · "))
        print("Most CPU: " + recap.topByCpu.map { "\($0.name) \(RecapFormat.cpu($0.averageCpuPercent))" }.joined(separator: " · "))
    }

    static func kindLabel(_ name: String) -> String {
        WorkloadKind.allCases.first { $0.commandName == name }?.commandLabel ?? name
    }

    private static func detailText(_ item: WorkloadSummary) -> String {
        var parts = ["\(item.processCount) process\(item.processCount == 1 ? "" : "es")"]
        if !item.ports.isEmpty { parts.append("port " + item.ports.prefix(3).map(String.init).joined(separator: ", ")) }
        if let command = item.command { parts.append(command) }
        return parts.joined(separator: " · ")
    }

    private static func pressureLabel(_ pressure: String) -> String {
        pressure == MemoryPressure.unknown.rawValue ? "Unavailable" : pressure.capitalized
    }

    static func shellQuoted(_ text: String) -> String {
        text.allSatisfy { $0.isLetter || $0.isNumber || "-_.".contains($0) } ? text : "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
