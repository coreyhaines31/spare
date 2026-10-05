import AppKit
import SwiftUI
import SpareCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    let monitor = Monitor()
    private var item: NSStatusItem!
    private let popover = NSPopover()
    private var window: NSWindow?
    private var recapWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "leaf", accessibilityDescription: "Spare")
        item.button?.target = self
        item.button?.action = #selector(toggle)
        item.button?.toolTip = "Spare — your Mac at a glance"
        popover.contentSize = NSSize(width: SpareLayout.width, height: SpareLayout.height)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: Dashboard(monitor: monitor))
        monitor.onUpdate = { [weak self] health in
            self?.item.button?.image = NSImage(systemSymbolName: health.level > 0 ? "exclamationmark.circle" : "leaf", accessibilityDescription: "Spare: \(health.title)")
            self?.item.button?.toolTip = "Spare — \(health.title)"
        }
        monitor.start()
        monitor.onOpenWindow = { [weak self] in self?.showWindow() }
        monitor.onOpenRecap = { [weak self] in self?.showRecap() }
        if CommandLine.arguments.contains("--window") { showWindow() }
        else { toggle() }
    }

    func applicationWillTerminate(_ notification: Notification) { monitor.stop() }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    private func showRecap() {
        popover.performClose(nil)
        if recapWindow == nil {
            let created = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 780),
                                   styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            created.title = "Spare — Recap"
            created.contentView = NSHostingView(rootView: RecapView(monitor: monitor))
            created.contentMinSize = NSSize(width: 640, height: 540)
            created.setFrameAutosaveName("SpareRecap")
            created.center()
            created.isReleasedWhenClosed = false
            recapWindow = created
        }
        recapWindow?.deminiaturize(nil)
        recapWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showWindow() {
        popover.performClose(nil)
        if window == nil {
            let created = NSWindow(contentRect: NSRect(x: 0, y: 0, width: SpareLayout.width, height: SpareLayout.height),
                                   styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            created.title = "Spare"
            created.contentView = NSHostingView(rootView: Dashboard(monitor: monitor))
            created.center()
            created.isReleasedWhenClosed = false
            window = created
        }
        window?.deminiaturize(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func toggle() {
        if popover.isShown { popover.performClose(nil) }
        else if let button = item.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

if CommandLine.arguments.contains("--snapshot") {
    let sampler = Sampler()
    _ = sampler.sample()
    Thread.sleep(forTimeInterval: 1)
    if let snapshot = sampler.sample() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(snapshot.system), let text = String(data: data, encoding: .utf8) { print(text) }
        print("Readable processes: \(snapshot.processes.count)")
    } else { exit(1) }
} else {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.run()
}
