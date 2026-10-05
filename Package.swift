// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Spare",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Spare", targets: ["Spare"])],
    targets: [
        .target(name: "CSpare"),
        .target(name: "SpareCore", dependencies: ["CSpare"]),
        .executableTarget(name: "Spare", dependencies: ["SpareCore"]),
        .testTarget(name: "SpareCoreTests", dependencies: ["SpareCore", "CSpare"])
    ]
)
