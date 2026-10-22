// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "EpoBrowser",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(name: "EpoBrowser", path: "Sources/EpoBrowser")
    ]
)
