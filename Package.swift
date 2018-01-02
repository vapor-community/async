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
        .testTarget(name: "AsyncTests", dependencies: ["Async"]),
    ]
)

#if os(Linux)
    package.dependencies.append(.package(url: "https://github.com/vapor/cepoll.git", from: "0.2.0"))
#endif
