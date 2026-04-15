// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeStats",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ClaudeStats", targets: ["ClaudeStats"])
    ],
    targets: [
        .executableTarget(
            name: "ClaudeStats",
            path: "Sources/ClaudeStats"
        )
    ]
)
