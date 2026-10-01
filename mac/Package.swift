// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QuickStick",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "QuickStick",
            path: "Sources/QuickStick",
            resources: [.process("../../Resources")]
        )
    ]
)
