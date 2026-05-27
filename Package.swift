// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// MARK: - Dependencies

var packageDependencies: [Package.Dependency] = [
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
    .package(url: "https://github.com/tuist/Noora", from: "0.54.0"),
    .package(url: "https://github.com/mattt/swift-toml", from: "2.0.0"),
    .package(url: "https://github.com/mattt/swift-yyjson", from: "0.5.0"),
    .package(url: "https://github.com/huggingface/swift-jinja.git", from: "2.0.0"),
]

// swift-docc-plugin uses snippet APIs unavailable on Windows.
#if !os(Windows)
    packageDependencies.append(
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.5")
    )
#endif

// MARK: - Package

let package = Package(
    name: "baton",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "baton", targets: ["BatonCLI"]),
        .library(name: "BatonKit", targets: ["BatonKit"]),
    ],
    dependencies: packageDependencies,
    targets: [
        // Core domain logic — no UI dependencies.
        .target(
            name: "BatonKit",
            dependencies: [
                .product(name: "TOML", package: "swift-toml"),
                .product(name: "YYJSON", package: "swift-yyjson"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),

        // GitHub integration via the `gh` CLI.
        .target(
            name: "BatonForge",
            dependencies: [
                "BatonKit",
                .product(name: "Logging", package: "swift-log"),
            ]
        ),

        // The `baton` executable: commands, terminal UI, rendering.
        .executableTarget(
            name: "BatonCLI",
            dependencies: [
                "BatonKit",
                "BatonForge",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Noora", package: "Noora"),
                .product(name: "Jinja", package: "swift-jinja"),
            ]
        ),

        // MARK: - Tests

        .testTarget(
            name: "BatonKitTests",
            dependencies: ["BatonKit"]
        ),
        .testTarget(
            name: "BatonForgeTests",
            dependencies: ["BatonForge", "BatonKit"]
        ),
        .testTarget(
            name: "BatonCLITests",
            dependencies: ["BatonCLI"]
        ),
    ]
)
