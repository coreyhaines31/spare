// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Spare",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Spare", targets: ["Spare"]), .executable(name: "SpareCLI", targets: ["SpareCLI"])],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
        // Shared Brushed popover components. Pinned to the PanelKit branch until it lands on main.
        .package(url: "https://github.com/coreyhaines31/mac-app-kit", branch: "feature/2-panelkit")
    ],
    targets: [
        .target(name: "CSpare"),
        .target(name: "SpareCore", dependencies: ["CSpare"]),
        .executableTarget(name: "Spare", dependencies: ["SpareCore", .product(name: "Sparkle", package: "Sparkle"),
                                                     .product(name: "PanelKit", package: "mac-app-kit")]),
        .executableTarget(name: "SpareCLI", dependencies: ["SpareCore", "CSpare"]),
        .testTarget(name: "SpareCoreTests", dependencies: ["SpareCore", "CSpare"])
    ]
)
