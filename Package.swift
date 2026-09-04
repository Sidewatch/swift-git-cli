// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "GitKit",
    platforms: [.macOS(.v14)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "GitKit",
            targets: ["GitKit"]),
    ],
    dependencies: [
        // The shared subprocess runner. GitKit used to hand-roll two near-identical
        // Process/Pipe runners; the drain-both-streams contract lives in one place now.
        .package(path: "../swift-process-runner"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        .target(
            name: "GitKit",
            dependencies: [.product(name: "ProcessRunner", package: "swift-process-runner")],
            path: "Sources",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "GitKitTests",
            dependencies: ["GitKit"],
            path: "Tests"
        ),
    ]
)
