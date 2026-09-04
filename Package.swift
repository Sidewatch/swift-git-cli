// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "GitCLI",
    platforms: [.macOS(.v14)],
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
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "GitCLITests",
            dependencies: ["GitCLI"],
            path: "Tests"
        ),
    ]
)
