// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "CoupleMon",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CoupleMon", targets: ["CoupleMon"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/supabase/supabase-swift.git",
            exact: "2.49.0"
        ),
    ],
    targets: [
        .executableTarget(
            name: "CoupleMon",
            dependencies: [
                .product(name: "Realtime", package: "supabase-swift"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "CoupleMonTests", dependencies: ["CoupleMon"]),
    ]
)
