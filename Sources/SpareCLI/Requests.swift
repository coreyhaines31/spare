import AppKit
import SpareCore
import CSpare

/// Sends a request to the running app, which asks the person, then reports what they decided.
enum Requests {
    private struct Result: Encodable {
        var outcome: String
        var message: String
        var closed: Bool?
    }

    static func quit(_ query: String, options: Options) -> Never {
        let reading = Reading.take()
        let workload = reading.resolve(query)
        guard workload.canStop else {
            Output.fail("Spare doesn’t close \(workload.name) from here. \(workload.consequence)")
        }
        send(.init(action: .quit, target: workload.id, requester: reading.requester), options: options)
    }

    static func send(_ message: CommandRequest.Message, options: Options) -> Never {
        guard runningSpare != nil else {
            Output.fail("Spare isn’t running, so there’s no one to approve this. Start it with `spare open`, then try again.")
        }
        let center = DistributedNotificationCenter.default()
        var waiting = false
        var announced = false
        var reply: CommandRequest.Reply?
        let observer = center.addObserver(forName: CommandRequest.reply, object: nil, queue: nil) { notification in
            guard let received = CommandRequest.Reply(userInfo: notification.userInfo), received.id == message.id else { return }
            if received.outcome == .waiting { waiting = true } else { reply = received }
        }
        defer { center.removeObserver(observer) }
        signal(SIGINT, SIG_IGN)
        let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        interrupt.setEventHandler {
            withdraw(message)
            finish(Result(outcome: "cancelled", message: "Withdrew the request. Nothing was closed."), code: 4)
        }
        interrupt.resume()

        center.postNotificationName(CommandRequest.request, object: nil, userInfo: message.userInfo, deliverImmediately: true)
        let started = Date()
        while reply == nil {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.2))
            let elapsed = Date().timeIntervalSince(started)
            if !waiting, reply == nil, elapsed > 5 {
                withdraw(message)
                Output.fail("Spare didn’t respond. Make sure Spare 0.14 or later is running, then try again.")
            }
            if reply == nil, elapsed > options.timeout {
                withdraw(message)
                finish(Result(outcome: "timed-out", message: "No answer in Spare’s panel within \(Int(options.timeout)) seconds, so nothing was closed."), code: 4)
            }
            if waiting, !announced {
                announced = true
                Output.note("Waiting for approval in Spare’s panel. Press Control-C to withdraw the request.")
            }
        }
        guard let reply else { exit(1) }
        switch reply.outcome {
        case .approved:
            Output.note(reply.message)
            let closed = waitForExit(reply.identities)
            finish(Result(outcome: "approved", message: closed
                ? "Approved, and it has closed."
                : "Approved, but it’s still running. It may be asking to save; check the app.", closed: closed), code: 0)
        case .declined:
            finish(Result(outcome: "declined", message: "Declined in Spare’s panel. Nothing was closed."), code: 4)
        default:
            finish(Result(outcome: reply.outcome.rawValue, message: reply.message), code: 1)
        }
    }

    private static func withdraw(_ message: CommandRequest.Message) {
        DistributedNotificationCenter.default().postNotificationName(CommandRequest.cancel, object: nil,
                                                                     userInfo: ["id": message.id], deliverImmediately: true)
    }

    /// Gives apps a few seconds to quit, since they may close windows or save first.
    private static func waitForExit(_ identities: [ProcessIdentity]) -> Bool {
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if !identities.contains(where: { spare_matches($0.pid, $0.started) }) { return true }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return false
    }

    private static func finish(_ result: Result, code: Int32) -> Never {
        if Output.json { Output.print(result) } else { print(result.message) }
        exit(code)
    }
}
