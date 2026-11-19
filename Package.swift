// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FocusNow",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FocusNowCore", targets: ["FocusNowCore"]),
    ],
    targets: [
        .target(name: "FocusNowCore"),
        .executableTarget(name: "FocusNow", dependencies: ["FocusNowCore"]),
        .testTarget(name: "FocusNowCoreTests", dependencies: ["FocusNowCore"]),
    ]
)
