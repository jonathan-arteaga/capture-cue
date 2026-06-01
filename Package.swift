// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "capture-cue",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "CaptureCue", targets: ["CaptureCue"])
    ],
    targets: [
        .executableTarget(
            name: "CaptureCue",
            path: "Sources/CaptureCue",
            resources: [
                .process("../../Resources")
            ],
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny")
            ]
        ),
        .testTarget(
            name: "CaptureCueTests",
            dependencies: ["CaptureCue"],
            path: "Tests/CaptureCueTests"
        )
    ]
)
