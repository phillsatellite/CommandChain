// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CommandCache",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "CommandCache", targets: ["CommandCache"]),
    ],
    targets: [
        // Pure logic: history rules, categories, shell hook, inbox parsing. No UI.
        .target(name: "CommandCacheCore"),
        // The menu bar app (SwiftUI).
        .executableTarget(name: "CommandCache", dependencies: ["CommandCacheCore"]),
        .testTarget(name: "CommandCacheCoreTests", dependencies: ["CommandCacheCore"]),
    ]
)
