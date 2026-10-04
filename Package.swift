// swift-tools-version:5.10
import PackageDescription

// The single build definition. `scripts/package.sh` builds with SwiftPM and wraps the binary
// in PhotoFlow.app; Xcode can open this file directly.
let package = Package(
    name: "PhotoFlow",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "PhotoFlow",
            path: ".",
            exclude: ["Assets.xcassets", "Resources", "scripts", "Tests", "README.md", "build", "dist"],
            sources: ["PhotoFlowApp.swift", "Models", "Services", "ViewModels", "Views"],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("Vision"),
                .linkedFramework("CoreLocation"),
            ]
        ),
        .testTarget(
            name: "PhotoFlowTests",
            dependencies: ["PhotoFlow"],
            path: "Tests/PhotoFlowTests"
        ),
    ]
)
