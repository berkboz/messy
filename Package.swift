// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Messy",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "Messy",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Messy",
            // build.sh puts Sparkle.framework in Contents/Frameworks.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        )
    ]
)
