import Darwin
import Foundation

/// What a helper process does inside a multi-process app such as a browser or Electron app.
public enum HelperRole {
    case main, session, page, extensionHost, graphics, network, utility, other

    /// Tabs, extensions, and separate sessions can be ended on their own without taking the app down.
    public var canEnd: Bool { self == .page || self == .extensionHost || self == .session }

    /// Why a process can't be ended from Spare, for roles that can't.
    public var lockedReason: String? {
        switch self {
        case .main: return "This is the app itself. Quit the app to free its memory."
        case .graphics, .network, .utility, .other: return "The app needs this process to keep running. Quit the whole app to free it."
        default: return nil
        }
    }

    public func label(browser: Bool) -> String {
        switch self {
        case .main: return "App"
        case .session: return "Separate session"
        case .page: return browser ? "Tab or site" : "Window content"
        case .extensionHost: return "Extension"
        case .graphics: return "Graphics"
        case .network: return "Network"
        case .utility: return "Utility"
        case .other: return "Helper"
        }
    }

    public func pluralLabel(browser: Bool) -> String {
        switch self {
        case .main: return "App"
        case .session: return "Separate sessions"
        case .page: return browser ? "Tabs and sites" : "Window content"
        case .extensionHost: return "Extensions"
        case .graphics: return "Graphics"
        case .network: return "Network"
        case .utility: return "Utilities"
        case .other: return "Helpers"
        }
    }

    public func consequence(browser: Bool) -> String {
        switch self {
        case .page where browser:
            return "The tabs this process runs will show a crash page (“Aw, Snap!” in Chrome). Reload a tab to bring it back. Unsaved form input in those tabs is lost."
        case .page:
            return "A window or view in this app may go blank or reload. Unsaved input in it may be lost."
        case .extensionHost:
            return "This extension stops until the browser restarts it or you reload it from the extensions page."
        case .session:
            return "Closes this separate session with all of its windows and tabs. If an automation tool or agent started it, that tool may report an error."
        default:
            return "The app depends on this process. Quit the whole app instead if you need the memory back."
        }
    }

    /// Classifies a helper from its Chromium/Electron `--type` arguments or WebKit process name.
    /// `mainPath` is the app's own executable; another process running it without `--type` is a separate session.
    public static func classify(name: String, arguments: [String], isMain: Bool,
                                path: String = "", mainPath: String = "") -> HelperRole {
        if isMain { return .main }
        let type = arguments.first { $0.hasPrefix("--type=") }.map { String($0.dropFirst(7)) }
        if type == nil, !arguments.isEmpty, !mainPath.isEmpty, path == mainPath { return .session }
        switch type {
        case "renderer":
            return arguments.contains("--extension-process") ? .extensionHost : .page
        case "gpu-process":
            return .graphics
        case "utility":
            return arguments.contains { $0.hasPrefix("--utility-sub-type=network.") } ? .network : .utility
        case .some:
            return .utility
        case nil:
            break
        }
        if name.hasSuffix(".WebContent") || name.hasSuffix("Web Content") { return .page }
        if name.hasSuffix(".GPU") { return .graphics }
        if name.hasSuffix(".Networking") { return .network }
        return .other
    }
}

public enum ProcessArguments {
    private static var cache: [ProcessIdentity: [String]] = [:]

    /// Launch arguments don't change for a process's lifetime, so each is read once. Call from the main thread.
    public static func cached(for identity: ProcessIdentity) -> [String] {
        if let cached = cache[identity] { return cached }
        if cache.count > 4000 { cache.removeAll() }
        let arguments = read(pid: identity.pid)
        cache[identity] = arguments
        return arguments
    }

    /// Reads a process's launch arguments. Returns an empty list when macOS doesn't allow it.
    public static func read(pid: Int32) -> [String] {
        var mib = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return [] }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return [] }
        return parse(Array(buffer.prefix(size)))
    }

    /// Parses a KERN_PROCARGS2 buffer: argc, the executable path, padding, then argc NUL-terminated arguments.
    public static func parse(_ bytes: [UInt8]) -> [String] {
        guard bytes.count > 4 else { return [] }
        let argc = bytes.prefix(4).withUnsafeBytes { Int($0.loadUnaligned(as: Int32.self)) }
        var index = 4
        while index < bytes.count, bytes[index] != 0 { index += 1 }
        while index < bytes.count, bytes[index] == 0 { index += 1 }
        var arguments: [String] = []
        while arguments.count < argc, index < bytes.count {
            let start = index
            while index < bytes.count, bytes[index] != 0 { index += 1 }
            arguments.append(String(decoding: bytes[start..<index], as: UTF8.self))
            index += 1
        }
        return arguments
    }
}
