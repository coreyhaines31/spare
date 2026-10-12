import XCTest
@testable import SpareCore

final class DockerSettingsTests: XCTestCase {
    func testReadsConfiguredLimitOrFallsBackToHalfOfMemory() {
        let physical: UInt64 = 48 << 30
        XCTAssertEqual(DockerSettings.parse(Data(#"{"MemoryMiB": 8192}"#.utf8), physical: physical),
                       .init(bytes: 8 << 30, isDefault: false))
        XCTAssertEqual(DockerSettings.parse(Data(#"{"memoryMiB": 4096}"#.utf8), physical: physical),
                       .init(bytes: 4 << 30, isDefault: false))
        XCTAssertEqual(DockerSettings.parse(Data(#"{"AutoStart": true}"#.utf8), physical: physical),
                       .init(bytes: 24 << 30, isDefault: true))
        XCTAssertEqual(DockerSettings.parse(Data(), physical: physical), .init(bytes: 24 << 30, isDefault: true))
    }
}
