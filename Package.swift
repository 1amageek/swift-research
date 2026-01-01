// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftResearch",
    platforms: [
        .macOS(.v15),
        .iOS(.v18)
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
        .package(url: "https://github.com/1amageek/OpenFoundationModels-Ollama.git", branch: "main"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.7.0"),
    ],
    targets: [
        .target(
            name: "SwiftResearch",
            dependencies: [
                .product(name: "Selenops", package: "Selenops"),
                .product(name: "SwiftAgent", package: "SwiftAgent"),
                .product(name: "RemarkKit", package: "Remark"),
                .product(name: "OpenFoundationModelsOllama", package: "OpenFoundationModels-Ollama"),
            ]
        ),
        .executableTarget(
            name: "ResearchCLI",
            dependencies: [
                "SwiftResearch",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "SwiftResearchTests",
            dependencies: ["SwiftResearch"]
        ),
    ]
)
