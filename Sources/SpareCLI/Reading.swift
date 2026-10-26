import AppKit
import SpareCore

let spareBundleID = "com.spareformac.Spare"

/// One reading of the Mac, grouped the same way the panel groups it.
struct Reading {
    let snapshot: Snapshot
    let workloads: [Workload]
    let records: [Int32: ProcessRecord]
    let appNames: [Int32: String]
    let resolver: ProjectResolver
    let agents: [ProcessIdentity: AgentActivity]

    /// CPU is measured between two samples, so this takes about a second.
    static func take() -> Reading {
        let sampler = Sampler()
        _ = sampler.sample()
        Thread.sleep(forTimeInterval: 1)
        guard let snapshot = sampler.sample() else { Output.fail("Couldn’t read this Mac’s processes. Try again in a moment.") }
        let running = NSWorkspace.shared.runningApplications
        let apps = running.compactMap { app -> AppRecord? in
            guard let url = app.bundleURL, let name = app.localizedName else { return nil }
            return AppRecord(pid: app.processIdentifier, name: name, path: url.path,
                             canQuit: app.activationPolicy == .regular && app.bundleIdentifier != spareBundleID)
        }
        let resolver = ProjectResolver()
        return Reading(snapshot: snapshot,
                       workloads: WorkloadGrouper.group(snapshot.processes, apps: apps, project: resolver.project),
                       records: Dictionary(snapshot.processes.map { ($0.identity.pid, $0) }, uniquingKeysWith: { first, _ in first }),
                       appNames: Dictionary(apps.map { ($0.pid, $0.name) }, uniquingKeysWith: { first, _ in first }),
                       resolver: resolver,
                       agents: AgentActivityTracker().record(snapshot.processes, ready: snapshot.ready,
                                                             claude: ClaudeSessionStatus.read(), now: 0))
    }

    func summary(_ workload: Workload) -> WorkloadSummary {
        WorkloadSummary(workload, command: command(for: workload), activity: workload.activity(in: agents))
    }

    func command(for workload: Workload) -> String? {
        workload.commandSummary { ProcessArguments.cached(for: $0) }
    }

    func origin(of process: ProcessRecord) -> SessionOrigin {
        SessionOrigin.find(for: process, in: records, apps: appNames,
                           arguments: { pid in records[pid].map { ProcessArguments.cached(for: $0.identity) } ?? [] },
                           project: resolver.project)
    }

    var leftovers: [LeftoverSession] {
        Leftovers.find(workloads, records: records, apps: appNames, arguments: { ProcessArguments.cached(for: $0) },
                       project: resolver.project)
    }

    /// Strays plus the candidates a live agent holds.
    var strays: [StrayProcess] {
        StrayProcesses.find(records: records, arguments: { ProcessArguments.cached(for: $0) }, project: resolver.project)
    }

    /// Who is running this command, such as "Claude in website", found from its parent processes.
    var requester: String? {
        records[getpid()].flatMap { origin(of: $0).requesterName }
    }

    /// The one workload a name means, or an error listing the candidates.
    func resolve(_ query: String) -> Workload {
        switch WorkloadLookup.find(query, in: workloads.filter { $0.kind != .background }) {
        case .found(let workload): return workload
        case .ambiguous(let matches):
            let names = matches.prefix(8).map { "  \($0.name)  (\($0.kind.commandLabel), id: \($0.id))" }.joined(separator: "\n")
            Output.fail("“\(query)” matches more than one item. Use a fuller name or an id:\n\(names)")
        case .notFound:
            Output.fail("Nothing called “\(query)” is running. Run `spare list` to see names.")
        }
    }
}

/// The running Spare app, if there is one.
var runningSpare: NSRunningApplication? {
    NSRunningApplication.runningApplications(withBundleIdentifier: spareBundleID).first
}

/// Spare.app, found from this command's own location inside it, or from Launch Services.
var spareAppURL: URL? {
    if let executable = Bundle.main.executableURL?.resolvingSymlinksInPath() {
        let app = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        if app.pathExtension == "app" { return app }
    }
    return NSWorkspace.shared.urlForApplication(withBundleIdentifier: spareBundleID)
}
