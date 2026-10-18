// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Messy",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Messy", path: "Sources/Messy")
    ]
)
