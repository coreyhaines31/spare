import XCTest
@testable import SpareCore

final class AppHelperTests: XCTestCase {
    func testChromiumHelpersAreClassifiedByType() {
        let helper = "Google Chrome Helper (Renderer)"
        XCTAssertEqual(HelperRole.classify(name: helper, arguments: ["x", "--type=renderer"], isMain: false), .page)
        XCTAssertEqual(HelperRole.classify(name: helper, arguments: ["--type=renderer", "--extension-process"], isMain: false), .extensionHost)
        XCTAssertEqual(HelperRole.classify(name: "Helper (GPU)", arguments: ["--type=gpu-process"], isMain: false), .graphics)
        XCTAssertEqual(HelperRole.classify(name: "Helper", arguments: ["--type=utility", "--utility-sub-type=network.mojom.NetworkService"], isMain: false), .network)
        XCTAssertEqual(HelperRole.classify(name: "Helper", arguments: ["--type=utility", "--utility-sub-type=storage.mojom.StorageService"], isMain: false), .utility)
        XCTAssertEqual(HelperRole.classify(name: "Google Chrome", arguments: [], isMain: true), .main)
        XCTAssertEqual(HelperRole.classify(name: "Mystery", arguments: [], isMain: false), .other)
    }

    func testAnotherInstanceOfTheAppIsASeparateSession() {
        let path = "/Applications/Chrome.app/Contents/MacOS/Chrome"
        XCTAssertEqual(HelperRole.classify(name: "Chrome", arguments: [path, "--user-data-dir=/tmp/a"], isMain: false,
                                           path: path, mainPath: path), .session)
        XCTAssertEqual(HelperRole.classify(name: "Chrome", arguments: [], isMain: false, path: path, mainPath: path), .other)
        XCTAssertTrue(HelperRole.session.canEnd)
        XCTAssertNil(HelperRole.session.lockedReason)
        XCTAssertNotNil(HelperRole.graphics.lockedReason)
    }

    func testWebKitProcessesAreClassifiedByName() {
        XCTAssertEqual(HelperRole.classify(name: "com.apple.WebKit.WebContent", arguments: [], isMain: false), .page)
        XCTAssertEqual(HelperRole.classify(name: "com.apple.WebKit.Networking", arguments: [], isMain: false), .network)
    }

    func testOnlyTabsAndExtensionsCanBeEnded() {
        XCTAssertTrue(HelperRole.page.canEnd)
        XCTAssertTrue(HelperRole.extensionHost.canEnd)
        XCTAssertFalse(HelperRole.main.canEnd)
        XCTAssertFalse(HelperRole.graphics.canEnd)
        XCTAssertFalse(HelperRole.network.canEnd)
    }

    func testParsesProcessArgumentsBuffer() {
        var bytes = withUnsafeBytes(of: Int32(3)) { Array($0) }
        bytes += Array("/Applications/App.app/Contents/MacOS/Helper".utf8) + [0, 0, 0]
        for argument in ["Helper", "--type=renderer", "--lang=en-US"] { bytes += Array(argument.utf8) + [0] }
        bytes += Array("PATH=/usr/bin".utf8) + [0]
        XCTAssertEqual(ProcessArguments.parse(bytes), ["Helper", "--type=renderer", "--lang=en-US"])
        XCTAssertEqual(ProcessArguments.parse([1, 0]), [])
    }

    func testReadsOwnArguments() {
        XCTAssertFalse(ProcessArguments.read(pid: getpid()).isEmpty)
    }
}
