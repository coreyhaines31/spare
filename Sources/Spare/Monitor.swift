import AppKit
import SwiftUI
import SpareCore
import CSpare
import UserNotifications
import ServiceManagement

final class Monitor: ObservableObject {
    @Published var recaps: [RecapPeriod: RecapReport] = [:]
    @Published var recapError: String?
    @Published var awayRecap: AwayRecap?
    private let awayTracker = AwayRecapTracker()
    private var sleeping = false
    private var sampleGeneration = 0
    private var sleepObservers: [NSObjectProtocol] = []
    @Published var savingHistory = UserDefaults.standard.object(forKey: "savingHistory") as? Bool ?? true
    private lazy var recapStore = RecapStore(url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Spare/recaps.json"))
    private var lastRecapPublish = Date.distantPast
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
    var onOpenRecap: (() -> Void)?
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
        let center = NSWorkspace.shared.notificationCenter
        sleepObservers = [
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.sleepChanged(true) },
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.sleepChanged(false) }
        ]
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.refresh() }
    }

    private func refresh() {
        guard !busy, !sleeping else { return }
        busy = true
        loginStatus = SMAppService.mainApp.status
        let apps = NSWorkspace.shared.runningApplications.compactMap { app -> AppRecord? in
            guard let url = app.bundleURL, let name = app.localizedName else { return nil }
            return AppRecord(pid: app.processIdentifier, name: name, path: url.path,
                canQuit: app.activationPolicy == .regular && app.processIdentifier != getpid())
        }
        let saveHistory = savingHistory
        let generation = sampleGeneration
        let idle = CGEventType(rawValue: ~0).map { CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: $0) } ?? 0
        queue.async { [self] in
            let snapshot = sampler.sample()
            let grouped = snapshot.map { WorkloadGrouper.group($0.processes, apps: apps, project: resolver.project) }
            recapStore.record(snapshot?.system, workloads: grouped ?? [], ready: snapshot?.ready ?? false, enabled: saveHistory)
            awayTracker.record(snapshot?.system, workloads: grouped ?? [], idleSeconds: idle, ready: snapshot?.ready ?? false,
                               enabled: saveHistory, now: Date())
            let latestAway = awayTracker.latest
            if Date().timeIntervalSince(lastRecapPublish) >= 30 { publishRecaps() }
            DispatchQueue.main.async { [self] in
                busy = false
                guard generation == sampleGeneration else { return }
                awayRecap = latestAway
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

    private func sleepChanged(_ isSleeping: Bool) {
        sleeping = isSleeping
        sampleGeneration += 1
        ready = false
        samples = []
        trendTracker.reset()
        memoryTrends = [:]
        history.pause(at: Date())
        activity = history.events
        queue.async { [self] in
            sampler.reset()
            recapStore.history.pause()
            awayTracker.pause()
            if isSleeping { recapStore.save() }
        }
        if !isSleeping { refresh() }
    }

    func dismissAwayRecap() {
        awayRecap = nil
        queue.async { [self] in awayTracker.dismiss() }
    }

    private func publishRecaps() {
        let now = Date()
        lastRecapPublish = now
        let reports = Dictionary(uniqueKeysWithValues: RecapPeriod.allCases.map { ($0, recapStore.history.report($0, at: now)) })
        let error = recapStore.error
        DispatchQueue.main.async { [self] in recaps = reports; recapError = error }
    }

    func refreshRecaps() { queue.async { [self] in publishRecaps() } }

    func setSavingHistory(_ enabled: Bool) {
        savingHistory = enabled
        if !enabled { awayRecap = nil }
        UserDefaults.standard.set(enabled, forKey: "savingHistory")
        queue.async { [self] in
            recapStore.history.pause()
            awayTracker.clear()
            recapStore.save()
            publishRecaps()
        }
    }

    func clearRecaps() {
        queue.async { [self] in
            if recapStore.clear() {
                awayTracker.clear()
                DispatchQueue.main.async { [self] in awayRecap = nil }
            }
            publishRecaps()
        }
    }

    func stop() {
        timer?.invalidate()
        for observer in sleepObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        sleepObservers = []
        queue.sync { recapStore.save() }
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
