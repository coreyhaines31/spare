import XCTest
@testable import SpareCore

final class OtherAccountProcessesTests: XCTestCase {
    func testParsesPsOutputWithSpacesInPaths() {
        let output = """
          400     1 157504 4729:22.02 /System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer
          912     1   2048   0:00.31 /Applications/Some App.app/Contents/MacOS/Some App
        bad line
        """
        XCTAssertEqual(OtherAccountProcesses.parse(output), [
            .init(pid: 400, parent: 1, residentBytes: 161_284_096, cpuSeconds: 283_762.02,
                  path: "/System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer"),
            .init(pid: 912, parent: 1, residentBytes: 2_097_152, cpuSeconds: 0.31, path: "/Applications/Some App.app/Contents/MacOS/Some App")
        ])
    }

    func testReadsEveryCPUTimeFormat() {
        XCTAssertEqual(OtherAccountProcesses.cpuSeconds("0:00.31"), 0.31)
        XCTAssertEqual(OtherAccountProcesses.cpuSeconds("892:44.63") ?? 0, 53_564.63, accuracy: 0.001)
        XCTAssertEqual(OtherAccountProcesses.cpuSeconds("2:03:04.50"), 7384.5)
        XCTAssertEqual(OtherAccountProcesses.cpuSeconds("1-02:03:04"), 93_784)
        XCTAssertNil(OtherAccountProcesses.cpuSeconds("soon"))
        XCTAssertNil(OtherAccountProcesses.cpuSeconds("12"))
    }

    func testOnlyShippedLocationsCount() {
        XCTAssertTrue(SystemProcessCatalog.isShipped("/usr/sbin/mDNSResponder"))
        XCTAssertTrue(SystemProcessCatalog.isShipped("/Library/Apple/System/Library/CoreServices/XProtect.app/Contents/MacOS/XProtect"))
        XCTAssertFalse(SystemProcessCatalog.isShipped("/Library/PrivilegedHelperTools/com.example.helper"))
        XCTAssertFalse(SystemProcessCatalog.isShipped("/opt/homebrew/bin/node"))
    }

    func testLiveReadIncludesSystemDaemons() {
        let rows = OtherAccountProcesses.read()
        XCTAssertTrue(rows.contains { $0.pid == 1 && $0.path == "/sbin/launchd" })
    }
}

final class SystemProcessCatalogTests: XCTestCase {
    func testLabelsShippedProcessesOnly() {
        let xprotect = ProcessRecord(pid: 900, name: "XProtect", path: "/Library/Apple/System/Library/CoreServices/XProtect.app/Contents/MacOS/XProtect")
        XCTAssertEqual(SystemProcessCatalog.entry(for: xprotect)?.category, "Security and privacy")
        let resolver = ProcessRecord(pid: 901, name: "mDNSResponder", path: "/usr/sbin/mDNSResponder")
        XCTAssertEqual(SystemProcessCatalog.entry(for: resolver)?.category, "Networking and devices")
        let lookalike = ProcessRecord(pid: 902, name: "mDNSResponder", path: "/Users/me/Downloads/mDNSResponder")
        XCTAssertNil(SystemProcessCatalog.entry(for: lookalike))
    }
}
