// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "GitCLI",
    platforms: [
        // `Process`-based CLI wrapping is desktop-only, so macOS is the sole target.
        .macOS(.v10_15)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "GitCLI",
            targets: ["GitCLI"]),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        .target(
            name: "GitCLI",
            path: "Sources",
            swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]
        ),
        .testTarget(
            name: "GitCLITests",
            dependencies: ["GitCLI"],
            path: "Tests"
        ),
    ]
)
