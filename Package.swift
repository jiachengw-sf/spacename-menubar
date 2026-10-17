// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SpaceName",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SpaceName",
            path: "Sources/SpaceName",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
