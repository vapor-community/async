// swift-tools-version:4.0
import PackageDescription

let package = Package(
    name: "Async",
    products: [
        .library(name: "Async", targets: ["Async"]),
    ],
    dependencies: [],
    targets: [
        .target(name: "Async"),
        .target(name: "Development", dependencies: ["Async"]),
        .testTarget(name: "AsyncTests", dependencies: ["Async"]),
    ]
)
