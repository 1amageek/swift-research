// swift-tools-version: 6.2
// SwiftUI Research App using SwiftResearch

import PackageDescription
import Foundation

// By default, uses Apple's FoundationModels framework.
// Set USE_OTHER_MODELS=1 to use OpenFoundationModels for development/testing.
let useOtherModels = ProcessInfo.processInfo.environment["USE_OTHER_MODELS"] != nil

let package = Package(
    name: "ResearchApp",
    platforms: [
        .macOS(.v26),
        .iOS(.v26)
    ],
    products: [
        .executable(
            name: "ResearchApp",
            targets: ["ResearchApp"]
        ),
        .library(
            name: "ResearchAppUI",
            targets: ["ResearchAppUI"]
        )
    ],
    dependencies: [
        .package(path: "../.."),
    ] + (useOtherModels ? [
        .package(path: "../../../OpenFoundationModels-Ollama"),
    ] : []),
    targets: [
        // Library target for UI components (enables Preview)
        .target(
            name: "ResearchAppUI",
            dependencies: [
                .product(name: "SwiftResearch", package: "swift-research"),
            ] + (useOtherModels ? [
                .product(name: "OpenFoundationModelsOllama", package: "OpenFoundationModels-Ollama"),
            ] : []),
            swiftSettings: [
                .enableExperimentalFeature("Observation")
            ] + (useOtherModels ? [.define("USE_OTHER_MODELS")] : [])
        ),
        // Executable target
        .executableTarget(
            name: "ResearchApp",
            dependencies: [
                "ResearchAppUI"
            ]
        )
    ]
)
