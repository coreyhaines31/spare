import AppKit
import SwiftUI
import SpareCore
import CSpare
import UserNotifications

final class Monitor: ObservableObject {
    @Published var workloads: [Workload] = []
    @Published var samples: [SystemSample] = []
    @Published var ready = false
    @Published var error: String?
    @Published var notice: String?
    @Published var alerts = UserDefaults.standard.bool(forKey: "alerts")
    private let queue = DispatchQueue(label: "com.spareformac.sampler", qos: .utility)
    private let sampler = Sampler()
    private let resolver = ProjectResolver()
    private var timer: Timer?
    private var lastAlert = Date.distantPast
    private var busy = false
    var onUpdate: ((Health) -> Void)?
    var health: Health { Health(samples: samples, ready: ready) }

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.refresh() }
    }

    private func refresh() {
        guard !busy else { return }
        busy = true
        let apps = NSWorkspace.shared.runningApplications.compactMap { app -> AppRecord? in
            guard let url = app.bundleURL, let name = app.localizedName else { return nil }
            return AppRecord(pid: app.processIdentifier, name: name, path: url.path,
                canQuit: app.activationPolicy == .regular && app.processIdentifier != getpid())
        }
        queue.async { [self] in
            let snapshot = sampler.sample()
            let grouped = snapshot.map { WorkloadGrouper.group($0.processes, apps: apps, project: resolver.project) }
            DispatchQueue.main.async { [self] in
                busy = false
                guard let snapshot, let grouped else {
                    error = "Spare couldn’t read system resources. It will try again shortly."
                    return
                }
                error = nil
                workloads = grouped
                ready = snapshot.ready
                samples.append(snapshot.system)
                if samples.count > 300 { samples.removeFirst(samples.count - 300) }
                onUpdate?(health)
                notifyIfNeeded()
            }
        }
    }

    func setAlerts(_ enabled: Bool) {
        if !enabled {
            alerts = false
            UserDefaults.standard.set(false, forKey: "alerts")
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { allowed, _ in
            DispatchQueue.main.async {
                self.alerts = allowed
                UserDefaults.standard.set(allowed, forKey: "alerts")
                if !allowed { self.notice = "Notifications are disabled. You can enable Spare in System Settings → Notifications." }
            }
        }
    }

    private func notifyIfNeeded() {
        guard alerts, health.level > 0, samples.count >= 20,
              Date().timeIntervalSince(lastAlert) > 600 else { return }
        let recent = Array(samples.suffix(20))
        guard recent.allSatisfy({ $0.pressure == .warning || $0.pressure == .critical }) ||
                recent.allSatisfy({ $0.cpu > 85 }) else { return }
        lastAlert = Date()
        let content = UNMutableNotificationContent()
        content.title = health.title
        content.body = health.message
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "pressure", content: content, trigger: nil))
    }

    func stop(_ workload: Workload) {
        guard workload.canStop else { return }
        if let identity = workload.appIdentity {
            guard spare_matches(identity.pid, identity.started),
                  let app = NSRunningApplication(processIdentifier: identity.pid),
                  app.bundleURL?.path == workload.appPath else {
                notice = "That app has already closed or restarted. Review its new reading before trying again."
                return
            }
            notice = app.terminate() ? "Quit requested for \(workload.name). The app may ask you to save your work." :
                "\(workload.name) did not accept the quit request. Open the app to close it yourself."
        } else if workload.kind == .development || workload.kind == .agent {
            let results = workload.processes.map { spare_stop($0.identity.pid, $0.identity.started) }
            let sent = results.filter { $0 == 0 }.count
            notice = "Stop requested for \(sent) of \(results.count) processes. Others may have exited or could not be stopped."
        }
    }
}
