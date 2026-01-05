// swift-tools-version: 6.2
// SwiftUI Research App using SwiftResearch

import PackageDescription

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
    ],
    targets: [
        // Library target for UI components (enables Preview)
        .target(
            name: "ResearchAppUI",
            dependencies: [
                .product(name: "SwiftResearch", package: "swift-research"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("Observation")
            ]
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
