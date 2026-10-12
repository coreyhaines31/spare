import AppKit
import ApplicationServices

/// Shortcuts into Google Chrome's own tools, which can name the tab behind each process.
enum ChromeShortcuts {
    enum Result {
        case opened, needsPermission, notFound
    }

    /// Brings Chrome forward and chooses Window → Task Manager through the Accessibility API.
    static func openTaskManager(pid: Int32) -> Result {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else { return .needsPermission }
        NSRunningApplication(processIdentifier: pid)?.activate()
        let app = AXUIElementCreateApplication(pid)
        guard let menuBar = element(app, kAXMenuBarAttribute),
              let window = children(menuBar).first(where: { title($0) == "Window" }),
              let menu = children(window).first,
              let item = children(menu).first(where: { title($0) == "Task Manager" }) else { return .notFound }
        return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success ? .opened : .notFound
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Opens System Settings at Privacy & Security → Accessibility.
    static func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    static func openPerformanceSettings(appURL: URL) {
        guard let url = URL(string: "chrome://settings/performance") else { return }
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
    }

    private static func element(_ parent: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement) // swiftlint:disable:this force_cast
    }

    private static func children(_ parent: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, kAXChildrenAttribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private static func title(_ element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}
