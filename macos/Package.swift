// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Nightride",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Nightride",
            path: "Sources/Nightride"
        )
    ]
)
