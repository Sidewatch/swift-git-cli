// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "GitCLI",
    platforms: [
        // `Process`-based CLI wrapping is desktop-only, so macOS is the sole target.
        // Raised from 10.15 to 12 to match swift-subprocess, which this now depends on:
        // SwiftPM requires a package's floor to be at least its dependencies' floors.
        .macOS(.v12)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "GitCLI",
            targets: ["GitCLI"]),
    ],
    dependencies: [
        // The shared subprocess runner. GitCLI used to hand-roll two near-identical
        // Process/Pipe runners; the drain-both-streams contract lives in one place now.
        .package(path: "../swift-subprocess"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        .target(
            name: "GitCLI",
            dependencies: [.product(name: "Subprocess", package: "swift-subprocess")],
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
