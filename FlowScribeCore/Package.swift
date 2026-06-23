// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FlowScribeCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "FlowScribeCore", targets: ["FlowScribeCore"])
    ],
    targets: [
        .target(name: "FlowScribeCore"),
        .testTarget(name: "FlowScribeCoreTests", dependencies: ["FlowScribeCore"])
    ]
)
