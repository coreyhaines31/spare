import AppKit
import SwiftUI
import SpareCore

/// A request from the `spare` command, shown in the panel until the person approves or declines it.
struct PendingRequest {
    typealias Result = (outcome: CommandRequest.Outcome, message: String, identities: [ProcessIdentity])
    let message: CommandRequest.Message
    let title: String
    let detail: String
    let action: String
    /// What the request would close, for a live warning if an agent in it is mid-task.
    var workload: Workload?
    let perform: () -> Result
}

/// Distributed notifications reach background apps only with immediate delivery, which needs the selector-based API.
final class CommandRequestListener: NSObject {
    private let handle: (Notification) -> Void

    init(handle: @escaping (Notification) -> Void) {
        self.handle = handle
        super.init()
        for name in [CommandRequest.request, CommandRequest.cancel] {
            DistributedNotificationCenter.default().addObserver(self, selector: #selector(received(_:)), name: name,
                                                                object: nil, suspensionBehavior: .deliverImmediately)
        }
    }

    deinit { DistributedNotificationCenter.default().removeObserver(self) }

    @objc private func received(_ notification: Notification) { handle(notification) }
}

extension Monitor {
    func listenForCommands() {
        requestListener = CommandRequestListener { [weak self] in self?.received($0) }
    }

    func approveRequest() {
        guard let request = pendingRequest else { return }
        pendingRequest = nil
        let result = request.perform()
        reply(request.message, result.outcome, result.message, identities: result.identities)
    }

    func declineRequest() {
        guard let request = pendingRequest else { return }
        pendingRequest = nil
        reply(request.message, .declined, "Declined.")
    }

    private func received(_ notification: Notification) {
        if notification.name == CommandRequest.cancel {
            if let id = notification.userInfo?["id"] as? String, pendingRequest?.message.id == id { pendingRequest = nil }
            return
        }
        guard let message = CommandRequest.Message(userInfo: notification.userInfo) else { return }
        guard pendingRequest == nil else {
            return reply(message, .busy, "Spare is already showing another request. Answer that one first, then try again.")
        }
        guard ready else { return reply(message, .busy, "Spare is still taking its first readings. Try again in a few seconds.") }
        switch message.action {
        case .quit: requestQuit(message)
        case .closeLeftovers: requestLeftovers(message)
        }
    }

    private func requestQuit(_ message: CommandRequest.Message) {
        let candidates = workloads.filter { $0.kind != .background }
        var workload = candidates.first { $0.id == message.target }
        if workload == nil {
            switch WorkloadLookup.find(message.target, in: candidates) {
            case .found(let match): workload = match
            case .ambiguous(let matches):
                return reply(message, .ambiguous, "“\(message.target)” matches \(matches.count) items: \(matches.prefix(4).map(\.name).joined(separator: ", ")).")
            case .notFound:
                return reply(message, .notFound, "Nothing called “\(message.target)” is running.")
            }
        }
        guard let workload else { return }
        guard workload.canStop else { return reply(message, .notAllowed, "Spare doesn’t close \(workload.name). \(workload.consequence)") }
        let verb = workload.kind == .application ? "Quit" : "Stop"
        present(PendingRequest(
            message: message, title: "\(verb) \(workload.name)?",
            detail: "\(requester(message)) asked Spare to \(verb.lowercased()) \(workload.name), which is using \(DisplayFormat.memory(workload.memory)). \(workload.consequence)",
            action: verb, workload: workload
        ) { [weak self] in
            guard let self, let current = workload.current(in: self.workloads), current.canStop else {
                return (.notFound, "\(workload.name) had already closed.", [])
            }
            self.stop(current)
            return (.approved, self.notice ?? "\(verb) requested for \(current.name).",
                    current.appIdentity.map { [$0] } ?? current.processes.map(\.identity))
        })
    }

    private func requestLeftovers(_ message: CommandRequest.Message) {
        let found = leftovers(matching: message.target)
        guard !found.isEmpty else { return reply(message, .notFound, "No leftover sessions right now.") }
        let memory = found.reduce(UInt64(0)) { $0 + $1.memory }
        let apps = Set(found.map(\.app.name)).sorted().joined(separator: ", ")
        let count = "\(found.count) leftover session\(found.count == 1 ? "" : "s")"
        let identities = Set(found.map(\.process.identity))
        present(PendingRequest(
            message: message, title: "Close \(count)?",
            detail: "\(requester(message)) asked Spare to close \(count) of \(apps), using \(DisplayFormat.memory(memory)). "
                + "Nothing is using them anymore. \(HelperRole.session.consequence(browser: true))",
            action: "Close"
        ) { [weak self] in
            guard let self else { return (.notFound, "Spare closed before answering.", []) }
            let current = self.leftovers(matching: message.target).filter { identities.contains($0.process.identity) }
            guard !current.isEmpty else { return (.notFound, "Those sessions had already closed.", []) }
            for (_, sessions) in Dictionary(grouping: current, by: \.app.id) {
                self.endSessions(sessions.map(\.process), in: sessions[0].app)
            }
            return (.approved, "Closing \(current.count) leftover session\(current.count == 1 ? "" : "s").", current.map(\.process.identity))
        })
    }

    private func leftovers(matching app: String) -> [LeftoverSession] {
        let names = Dictionary(NSWorkspace.shared.runningApplications.compactMap { running in
            running.localizedName.map { (running.processIdentifier, $0) }
        }, uniquingKeysWith: { first, _ in first })
        return Leftovers.find(workloads, records: processTable, apps: names, arguments: { ProcessArguments.cached(for: $0) },
                              project: originProject)
            .filter { app.isEmpty || $0.app.name.localizedCaseInsensitiveContains(app) }
    }

    private func requester(_ message: CommandRequest.Message) -> String {
        message.requester.map { String($0.prefix(60)) } ?? "A command-line tool"
    }

    private func present(_ request: PendingRequest) {
        pendingRequest = request
        reply(request.message, .waiting, "")
        onRequest?()
    }

    private func reply(_ message: CommandRequest.Message, _ outcome: CommandRequest.Outcome, _ text: String,
                       identities: [ProcessIdentity] = []) {
        let reply = CommandRequest.Reply(id: message.id, outcome: outcome, message: text, identities: identities)
        DistributedNotificationCenter.default().postNotificationName(CommandRequest.reply, object: nil,
                                                                     userInfo: reply.userInfo, deliverImmediately: true)
    }
}

struct CommandRequestBanner: View {
    let request: PendingRequest
    @ObservedObject var monitor: Monitor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(request.title, systemImage: "terminal").font(.headline)
            Text(request.detail).font(.callout).fixedSize(horizontal: false, vertical: true)
            if let workload = request.workload, let warning = workload.activity(in: monitor.agentActivity)?.stopWarning(agent: workload.name) {
                Label(warning, systemImage: "exclamationmark.triangle.fill").font(.callout.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Don’t \(request.action)") { monitor.declineRequest() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(request.action, role: .destructive) { monitor.approveRequest() }
                    .buttonStyle(.borderedProminent).tint(.red)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 12).padding(.vertical, 10)
    }
}
