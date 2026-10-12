import Foundation

/// Chrome's Memory Saver setting, read from its Local State file (performance_tuning.high_efficiency_mode).
public enum ChromeMemorySaver: Equatable {
    case off
    case on(maximum: Bool)
    case unknown

    public static var localState: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Google/Chrome/Local State")
    }

    public static func read(from url: URL = localState) -> ChromeMemorySaver {
        guard let data = try? Data(contentsOf: url) else { return .unknown }
        return parse(data)
    }

    /// Chromium stores state 0 for disabled and 2 for enabled, and aggressiveness 2 for Maximum.
    public static func parse(_ data: Data) -> ChromeMemorySaver {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tuning = root["performance_tuning"] as? [String: Any],
              let mode = tuning["high_efficiency_mode"] as? [String: Any],
              let state = mode["state"] as? Int else { return .unknown }
        switch state {
        case 0: return .off
        case 2: return .on(maximum: (mode["aggressiveness"] as? Int) == 2)
        default: return .unknown
        }
    }
}
