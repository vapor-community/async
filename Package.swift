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
    package.dependencies.append(.package(url: "https://github.com/IBM-Swift/CEpoll.git", .exact("0.1.1")))
#endif
