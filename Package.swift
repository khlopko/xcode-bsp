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
        .package(url: "https://github.com/apple/swift-log", from: "1.6.0")
    ],
    targets: [
        .executableTarget(
            name: "XcodeBSP",
            dependencies: [.product(name: "Logging", package: "swift-log")]
        ),
    ]
)
