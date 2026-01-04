// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import Foundation

// Set USE_FOUNDATION_MODELS=1 to use Apple's FoundationModels instead of OpenFoundationModels
// Example: USE_FOUNDATION_MODELS=1 swift build
let useFoundationModels = ProcessInfo.processInfo.environment["USE_FOUNDATION_MODELS"] != nil

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
            name: "research-cli",
            targets: ["ResearchCLI"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/1amageek/Selenops.git", from: "0.2.0"),
        .package(url: "https://github.com/1amageek/SwiftAgent.git", branch: "main"),
        .package(url: "https://github.com/1amageek/Remark.git", branch: "main"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.7.0"),
    ] + (useFoundationModels ? [] : [
        .package(url: "https://github.com/1amageek/OpenFoundationModels-Ollama.git", branch: "main"),
    ]),
    targets: [
        .target(
            name: "SwiftResearch",
            dependencies: [
                .product(name: "Selenops", package: "Selenops"),
                .product(name: "SwiftAgent", package: "SwiftAgent"),
                .product(name: "RemarkKit", package: "Remark"),
            ],
            swiftSettings: useFoundationModels ? [.define("USE_FOUNDATION_MODELS")] : []
        ),
        .executableTarget(
            name: "ResearchCLI",
            dependencies: [
                "SwiftResearch",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ] + (useFoundationModels ? [] : [
                .product(name: "OpenFoundationModelsOllama", package: "OpenFoundationModels-Ollama"),
            ]),
            swiftSettings: useFoundationModels ? [.define("USE_FOUNDATION_MODELS")] : []
        ),
        .testTarget(
            name: "SwiftResearchTests",
            dependencies: ["SwiftResearch"],
            swiftSettings: useFoundationModels ? [.define("USE_FOUNDATION_MODELS")] : []
        ),
    ]
)
