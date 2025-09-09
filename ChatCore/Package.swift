// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ChatCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ChatCore", targets: ["ChatCore"])
    ],
    targets: [
        .target(name: "ChatCore", dependencies: []),
        .testTarget(name: "ChatCoreTests", dependencies: ["ChatCore"])    ]
)
