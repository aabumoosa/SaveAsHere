// swift-tools-version: 6.0
import PackageDescription

// AXUIElement is not Sendable and this agent is single-threaded on the main run
// loop, so strict Swift 6 concurrency checking costs noise and buys nothing here.
let swift5 = [SwiftSetting.swiftLanguageMode(.v5)]

let package = Package(
    name: "SaveAsHere",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "AXKit", swiftSettings: swift5),
        .target(name: "SaveAsCore", swiftSettings: swift5),
        .executableTarget(
            name: "SaveAsHere",
            dependencies: ["AXKit", "SaveAsCore"],
            swiftSettings: swift5
        ),
        .testTarget(
            name: "SaveAsCoreTests",
            dependencies: ["SaveAsCore"],
            swiftSettings: swift5
        ),
    ]
)
