import Foundation

/// Requests the `spare` command sends to the running app, which asks the person before acting.
/// They travel as distributed notifications with string-only user info.
public enum CommandRequest {
    public static let request = Notification.Name("com.spareformac.Spare.command.request")
    public static let reply = Notification.Name("com.spareformac.Spare.command.reply")
    public static let cancel = Notification.Name("com.spareformac.Spare.command.cancel")

    public enum Action: String {
        case quit
        case closeLeftovers = "close-leftovers"
    }

    public struct Message: Equatable {
        public var id: String
        public var action: Action
        /// A workload id or name for `quit`; an optional app name for `closeLeftovers`.
        public var target: String
        public var requester: String?

        public init(id: String = UUID().uuidString, action: Action, target: String, requester: String?) {
            self.id = id
            self.action = action
            self.target = target
            self.requester = requester
        }

        public init?(userInfo: [AnyHashable: Any]?) {
            guard let info = userInfo as? [String: String], let id = info["id"],
                  let action = info["action"].flatMap(Action.init(rawValue:)) else { return nil }
            self.init(id: id, action: action, target: info["target"] ?? "", requester: info["requester"])
        }

        public var userInfo: [String: String] {
            var info = ["id": id, "action": action.rawValue, "target": target]
            info["requester"] = requester
            return info
        }
    }

    public enum Outcome: String {
        case approved, declined, busy, ambiguous
        case notFound = "not-found"
        case notAllowed = "not-allowed"
    }

    public struct Reply: Equatable {
        public var id: String
        public var outcome: Outcome
        public var message: String
        /// The processes the app asked to close, so the command can report when they're gone.
        public var identities: [ProcessIdentity]

        public init(id: String, outcome: Outcome, message: String, identities: [ProcessIdentity] = []) {
            self.id = id
            self.outcome = outcome
            self.message = message
            self.identities = identities
        }

        public init?(userInfo: [AnyHashable: Any]?) {
            guard let info = userInfo as? [String: String], let id = info["id"],
                  let outcome = info["outcome"].flatMap(Outcome.init(rawValue:)) else { return nil }
            let identities = (info["identities"] ?? "").split(separator: ",").compactMap { pair -> ProcessIdentity? in
                let parts = pair.split(separator: ":")
                guard parts.count == 2, let pid = Int32(parts[0]), let started = UInt64(parts[1]) else { return nil }
                return ProcessIdentity(pid: pid, started: started)
            }
            self.init(id: id, outcome: outcome, message: info["message"] ?? "", identities: identities)
        }

        public var userInfo: [String: String] {
            ["id": id, "outcome": outcome.rawValue, "message": message,
             "identities": identities.map { "\($0.pid):\($0.started)" }.joined(separator: ",")]
        }
    }
}
