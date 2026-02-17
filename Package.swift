// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "xcode-bsp",
    platforms: [.macOS(.v14)],
    products: [
        .executable(
            name: "xcode-bsp",
            targets: ["XcodeBSP"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log", from: "1.6.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.15.4"),
    ],
    targets: [
        .executableTarget(
            name: "XcodeBSP",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "SQLite", package: "SQLite.swift"),
            ]
        ),
        .testTarget(
            name: "XcodeBSPTests",
            dependencies: [
                "XcodeBSP",
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
    ]
)
