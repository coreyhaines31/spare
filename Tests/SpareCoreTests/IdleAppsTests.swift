import XCTest
@testable import SpareCore

final class IdleAppsTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "IdleAppsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testIdleTimeUsesLastActivationAndNeverOverstates() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let log = AppActivityLog(defaults: defaults(), now: start)
        // Never seen in front: counts from when Spare started, even if the app launched earlier.
        XCTAssertEqual(log.idleTime(appPath: "/A.app", launched: start.addingTimeInterval(-9000), now: start.addingTimeInterval(600)), 600)
        log.recordActivation(appPath: "/A.app", at: start.addingTimeInterval(100))
        XCTAssertEqual(log.idleTime(appPath: "/A.app", launched: nil, now: start.addingTimeInterval(400)), 300)
        // A relaunch after the last activation resets the clock.
        XCTAssertEqual(log.idleTime(appPath: "/A.app", launched: start.addingTimeInterval(300), now: start.addingTimeInterval(400)), 100)
    }

    func testActivationsPersistOnlyWhenSpareKeptWatching() {
        let store = defaults()
        let start = Date(timeIntervalSince1970: 1_000_000)
        let first = AppActivityLog(defaults: store, now: start)
        first.recordActivation(appPath: "/A.app", at: start)
        first.markWatching(at: start.addingTimeInterval(9_900))
        let relaunched = AppActivityLog(defaults: store, now: start.addingTimeInterval(10_000))
        XCTAssertEqual(relaunched.idleTime(appPath: "/A.app", launched: nil, now: start.addingTimeInterval(10_000)), 10_000)
        let afterGap = AppActivityLog(defaults: store, now: start.addingTimeInterval(20_000))
        XCTAssertEqual(afterGap.idleTime(appPath: "/A.app", launched: nil, now: start.addingTimeInterval(20_600)), 600)
    }

    func testClearForgetsActivations() {
        let store = defaults()
        let start = Date(timeIntervalSince1970: 1_000_000)
        let log = AppActivityLog(defaults: store, now: start)
        log.recordActivation(appPath: "/A.app", at: start.addingTimeInterval(500))
        log.clear()
        XCTAssertEqual(log.idleTime(appPath: "/A.app", launched: nil, now: start.addingTimeInterval(600)), 600)
        XCTAssertNil(store.object(forKey: "appLastActive"))
    }

    func testFindsQuittableIdleAppsWithMeaningfulMemory() {
        let big = Workload(id: "a", name: "Big", subtitle: "", explanation: "", consequence: "", kind: .application,
                           processes: [ProcessRecord(pid: 1, name: "Big", path: "/Big", memory: 900 << 20)], canStop: true)
        var small = big; small.id = "b"; small.processes = [ProcessRecord(pid: 2, name: "S", path: "/S", memory: 50 << 20)]
        var locked = big; locked.id = "c"; locked.canStop = false
        let found = IdleApps.find([big, small, locked]) { _ in 3 * 3600 }
        XCTAssertEqual(found.map(\.workload.id), ["a"])
        XCTAssertTrue(IdleApps.find([big]) { _ in 3600 }.isEmpty)
        XCTAssertEqual(IdleApps.describe(3 * 3600 + 120), "not used in 3h")
        XCTAssertEqual(IdleApps.describe(50 * 3600), "not used in 2 days")
    }
}
