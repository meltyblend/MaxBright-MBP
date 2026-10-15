// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "MaxBright",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "MaxBright", path: "Sources/MaxBright")
    ]
)
