// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "CoupleMon",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CoupleMon", targets: ["CoupleMon"]),
    ],
    targets: [
        .executableTarget(name: "CoupleMon"),
        .testTarget(name: "CoupleMonTests", dependencies: ["CoupleMon"]),
    ]
)
