// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "DemoApp",
    products: [
        .library(name: "DemoApp", targets: ["DemoApp"])
    ],
    targets: [
        .target(name: "DemoApp"),
        .testTarget(name: "DemoAppTests", dependencies: ["DemoApp"])
    ]
)
