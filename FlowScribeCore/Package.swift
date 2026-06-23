// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FlowScribeCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "FlowScribeCore", targets: ["FlowScribeCore"]),
        .executable(name: "flowscribe-cli", targets: ["flowscribe-cli"])
    ],
    targets: [
        .target(name: "FlowScribeCore"),
        .executableTarget(name: "flowscribe-cli", dependencies: ["FlowScribeCore"]),
        .testTarget(name: "FlowScribeCoreTests", dependencies: ["FlowScribeCore"])
    ]
)
