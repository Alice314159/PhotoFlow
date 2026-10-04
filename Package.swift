// swift-tools-version:5.10
import Foundation
import PackageDescription

// Command Line Tools keeps TestingMacros in plugins/testing, which the frontend
// does not load on its own. Full Xcode already registers that plugin.
let testingPluginDir = "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"
let testingPluginSettings: [SwiftSetting] =
    FileManager.default.fileExists(atPath: testingPluginDir + "/libTestingMacros.dylib")
    ? [.unsafeFlags(["-plugin-path", testingPluginDir])]
    : []

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
            exclude: ["Assets.xcassets", "Resources", "scripts", "Tests", "README.md", "dist"],
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
            path: "Tests/PhotoFlowTests",
            swiftSettings: testingPluginSettings
        ),
    ]
)
