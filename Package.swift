// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CommandChain",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "CommandChain", targets: ["CommandChain"]),
    ],
    targets: [
        // Pure logic: history rules, categories, shell hook, inbox parsing. No UI.
        .target(name: "CommandChainCore"),
        // The menu bar app (SwiftUI).
        .executableTarget(name: "CommandChain", dependencies: ["CommandChainCore"]),
        .testTarget(name: "CommandChainCoreTests", dependencies: ["CommandChainCore"]),
    ]
)
