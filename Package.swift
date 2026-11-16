// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Spare",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Spare", targets: ["Spare"]), .executable(name: "SpareCLI", targets: ["SpareCLI"])],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
        // PanelKit 0.2 from its development branch until 0.2.0 is tagged; then pin `from: "0.2.0"`.
        .package(url: "https://github.com/coreyhaines31/panelkit", branch: "development")
    ],
    targets: [
        .target(name: "CSpare"),
        .target(name: "SpareCore", dependencies: ["CSpare"]),
        .executableTarget(name: "Spare", dependencies: ["SpareCore", .product(name: "Sparkle", package: "Sparkle"),
                                                     .product(name: "PanelKit", package: "panelkit")]),
        .executableTarget(name: "SpareCLI", dependencies: ["SpareCore", "CSpare"]),
        .testTarget(name: "SpareCoreTests", dependencies: ["SpareCore", "CSpare"])
    ]
)
