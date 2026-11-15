// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GitHubInbox",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "GitHubInbox",
            path: "Sources/GitHubInbox",
            resources: [.process("Resources")]
        ),
    ]
)
