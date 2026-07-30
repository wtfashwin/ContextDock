// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ContextDock",
    platforms: [.macOS(.v15)],
    targets: [
        // Core logic: pure Swift, no UI. Testable without an app host.
        .target(
            name: "ContextDockKit",
            path: "Sources/ContextDockKit"
        ),
        // App shell: AppKit panel + SwiftUI content.
        .executableTarget(
            name: "ContextDockApp",
            dependencies: ["ContextDockKit"],
            path: "Sources/ContextDockApp"
        ),
        .testTarget(
            name: "ContextDockKitTests",
            dependencies: ["ContextDockKit"],
            path: "Tests/ContextDockKitTests"
        ),
    ]
)
