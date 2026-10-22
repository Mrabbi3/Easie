// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Easie",
    platforms: [.macOS(.v13)],
    targets: [
        // The conversion engine: no UI, usable from the app, the CLI and tests.
        .target(name: "EasieCore", path: "Sources/EasieCore"),
        // The Mac app (and its built-in `Easie convert` command line mode).
        .executableTarget(name: "Easie", dependencies: ["EasieCore"], path: "Sources/Easie"),
    ]
)
