// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "TerminatorCLI",
    platforms: [
        .macOS(.v14), // Updated from .v13
    ],
    products: [
        .executable(name: "terminator", targets: ["TerminatorCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "TerminatorCLI",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/TerminatorCLI"
        ),
        .testTarget(
            name: "TerminatorCLITests",
            dependencies: ["TerminatorCLI"],
            path: "Tests/TerminatorCLITests"
        ),
    ]
)
