import XCTest
@testable import SpareCore

final class ChromeMemorySaverTests: XCTestCase {
    private func parse(_ json: String) -> ChromeMemorySaver { ChromeMemorySaver.parse(Data(json.utf8)) }

    func testReadsMemorySaverStates() {
        XCTAssertEqual(parse(#"{"performance_tuning":{"high_efficiency_mode":{"state":0}}}"#), .off)
        XCTAssertEqual(parse(#"{"performance_tuning":{"high_efficiency_mode":{"state":2}}}"#), .on(maximum: false))
        XCTAssertEqual(parse(#"{"performance_tuning":{"high_efficiency_mode":{"state":2,"aggressiveness":2}}}"#), .on(maximum: true))
    }

    func testUnknownWhenMissingOrUnreadable() {
        XCTAssertEqual(parse("{}"), .unknown)
        XCTAssertEqual(parse("not json"), .unknown)
        XCTAssertEqual(parse(#"{"performance_tuning":{"high_efficiency_mode":{"state":1}}}"#), .unknown)
        XCTAssertEqual(ChromeMemorySaver.read(from: URL(fileURLWithPath: "/nonexistent")), .unknown)
    }
}
