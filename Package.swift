// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "astro-lens",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "astro-lens", targets: ["astro_lens"])
    ],
    targets: [
        .executableTarget(
            name: "astro_lens",
            path: "Sources/astro-lens",
            resources: [
                .process("../../Resources")
            ],
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny")
            ]
        ),
        .testTarget(
            name: "astro_lensTests",
            dependencies: ["astro_lens"],
            path: "Tests/astro-lens-tests"
        )
    ]
)
