// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Temiz",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Temiz", path: "Sources/Temiz")
    ]
)
