// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import Foundation

// By default, SwiftAgent uses Apple's FoundationModels framework.
// Set USE_OTHER_MODELS=1 to use OpenFoundationModels for development/testing with other LLM providers.
// Example: USE_OTHER_MODELS=1 swift build
let useOtherModels = ProcessInfo.processInfo.environment["USE_OTHER_MODELS"] != nil

let package = Package(
    name: "SwiftResearch",
    platforms: [
        .macOS(.v26),
        .iOS(.v26)
    ],
    products: [
        .library(
            name: "SwiftResearch",
            targets: ["SwiftResearch"]
        ),
        .executable(
            name: "research",
            targets: ["ResearchCLI"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/1amageek/Selenops.git", from: "0.3.0"),
        .package(url: "https://github.com/1amageek/SwiftAgent.git", branch: "main"),
        .package(url: "https://github.com/1amageek/Remark.git", branch: "main"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.7.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
    ] + (useOtherModels ? [
        .package(url: "https://github.com/1amageek/OpenFoundationModels-Ollama.git", branch: "main"),
    ] : []),
    targets: [
        .target(
            name: "SwiftResearch",
            dependencies: [
                .product(name: "Selenops", package: "Selenops"),
                .product(name: "SwiftAgent", package: "SwiftAgent"),
                .product(name: "RemarkKit", package: "Remark"),
            ],
            swiftSettings: useOtherModels ? [.define("USE_OTHER_MODELS")] : []
        ),
        .executableTarget(
            name: "ResearchCLI",
            dependencies: [
                "SwiftResearch",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ] + (useOtherModels ? [
                .product(name: "OpenFoundationModelsOllama", package: "OpenFoundationModels-Ollama"),
            ] : []),
            swiftSettings: useOtherModels ? [.define("USE_OTHER_MODELS")] : []
        ),
        .testTarget(
            name: "SwiftResearchTests",
            dependencies: ["SwiftResearch"] + (useOtherModels ? [
                .product(name: "OpenFoundationModelsOllama", package: "OpenFoundationModels-Ollama"),
            ] : []),
            swiftSettings: useOtherModels ? [.define("USE_OTHER_MODELS")] : []
        ),
    ]
)
