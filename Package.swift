// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "slurm-node-communication",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(
            name: "SlurmCommunication",
            targets: ["SlurmCommunication"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-subprocess", from: "0.3.0")
    ],
    targets: [
        .target(
            name: "SlurmCommunication",
            dependencies: [
                .product(name: "Subprocess", package: "swift-subprocess")
            ]
        ),
        .executableTarget(
            name: "Development",
            dependencies: [
                .target(name: "SlurmCommunication")
            ]
        ),
        .testTarget(
            name: "slurm-node-communicationTests",
            dependencies: ["SlurmCommunication"]
        ),
    ]
)
