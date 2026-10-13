// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Spare",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Spare", targets: ["Spare"]), .executable(name: "SpareCLI", targets: ["SpareCLI"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
    targets: [
        .target(name: "CSpare"),
        .target(name: "SpareCore", dependencies: ["CSpare"]),
        .executableTarget(name: "Spare", dependencies: ["SpareCore", .product(name: "Sparkle", package: "Sparkle")]),
        .executableTarget(name: "SpareCLI", dependencies: ["SpareCore", "CSpare"]),
        .testTarget(name: "SpareCoreTests", dependencies: ["SpareCore", "CSpare"])
    ]
)
