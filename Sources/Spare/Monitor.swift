import AppKit
import SwiftUI
import SpareCore
import CSpare
import UserNotifications
import ServiceManagement

final class Monitor: ObservableObject {
    @Published var memoryTrends: [String: MemoryTrend] = [:]
    private let trendTracker = MemoryTrendTracker()
    @Published var activity: [ActivityEvent] = []
    private let history = ActivityHistory()
    @Published var workloads: [Workload] = []
    @Published var samples: [SystemSample] = []
    @Published var ready = false
    @Published var error: String?
    @Published var notice: String?
    @Published var alerts = UserDefaults.standard.bool(forKey: "alerts")
    @Published var loginStatus = SMAppService.mainApp.status
    var onOpenWindow: (() -> Void)?
    var launchesAtLogin: Bool { loginStatus == .enabled || loginStatus == .requiresApproval }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginStatus = SMAppService.mainApp.status
            if loginStatus == .requiresApproval {
                notice = "Allow Spare in System Settings → General → Login Items to finish enabling launch at login."
            }
        } catch {
            loginStatus = SMAppService.mainApp.status
            notice = "Couldn’t change launch at login: \(error.localizedDescription)"
        }
    }

    private let queue = DispatchQueue(label: "com.spareformac.sampler", qos: .utility)
    private let sampler = Sampler()
    private let resolver = ProjectResolver()
    private var timer: Timer?
    private var lastAlert = Date.distantPast
    private var busy = false
    private var pendingStop: (name: String, tracker: StopFollowUp)?
    var onUpdate: ((Health) -> Void)?
    var health: Health { Health(samples: samples, ready: ready) }

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.refresh() }
    }

    private func refresh() {
        guard !busy else { return }
        busy = true
        loginStatus = SMAppService.mainApp.status
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
                    ready = false
                    trendTracker.reset()
                    memoryTrends = [:]
                    history.pause(at: Date())
                    activity = history.events
                    onUpdate?(health)
                    return
                }
                error = nil
                workloads = grouped
                checkStopProgress(snapshot.processes)
                ready = snapshot.ready
                memoryTrends = trendTracker.record(grouped, at: snapshot.system.date, ready: ready)
                samples.append(snapshot.system)
                if samples.count > 300 { samples.removeFirst(samples.count - 300) }
                history.record(samples: samples, workloads: grouped, ready: ready)
                activity = history.events
                onUpdate?(health)
                notifyIfNeeded()
            }
        }
    }

    func clearActivity() {
        history.clear()
        activity = []
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
        guard PressureAlert.isSustained(samples) else { return }
        lastAlert = Date()
        let content = UNMutableNotificationContent()
        content.title = health.title
        content.body = health.message
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "pressure", content: content, trigger: nil))
    }

    func stop(_ workload: Workload) {
        guard workload.canStop else { return }
        pendingStop = nil
        if let identity = workload.appIdentity {
            guard spare_matches(identity.pid, identity.started),
                  let app = NSRunningApplication(processIdentifier: identity.pid),
                  app.bundleURL?.path == workload.appPath else {
                notice = "That app has already closed or restarted. Review its new reading before trying again."
                return
            }
            if app.terminate() {
                trackStop(workload.name, identities: [identity])
                notice = "Quit requested for \(workload.name). Checking whether it closes; it may ask you to save."
            } else {
                notice = "\(workload.name) did not accept the quit request. Open the app to close it yourself."
            }
        } else if workload.kind == .development || workload.kind == .agent {
            let accepted = workload.processes.filter { spare_stop($0.identity.pid, $0.identity.started) == 0 }
            let sent = accepted.count
            let total = workload.processes.count
            if !accepted.isEmpty { trackStop(workload.name, identities: Set(accepted.map(\.identity))) }
            notice = "Stop requested for \(sent) of \(total) processes. Others may have exited or could not be stopped."
        }
    }
    private func trackStop(_ name: String, identities: Set<ProcessIdentity>) {
        pendingStop = (name, StopFollowUp(identities: identities, now: ProcessInfo.processInfo.systemUptime))
    }

    private func checkStopProgress(_ processes: [ProcessRecord]) {
        guard let pendingStop else { return }
        let result = pendingStop.tracker.result(visible: Set(processes.map(\.identity)), now: ProcessInfo.processInfo.systemUptime)
        switch result {
        case .waiting: return
        case .noLongerVisible:
            notice = "The requested processes for \(pendingStop.name) are no longer detected. Other sessions or restarted tasks may still appear."
        case .stillRunning(let count):
            notice = "\(pendingStop.name) still has \(count) requested process(es) running. Check for a save dialog or finish the task in its app. Spare won’t force it to close."
        }
        self.pendingStop = nil
    }

}
