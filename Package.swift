// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SessionBar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "SessionBar", path: "Sources/SessionBar")
    ]
)
