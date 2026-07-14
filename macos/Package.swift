// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Clawstatus",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Clawstatus", targets: ["Clawline"]),
    ],
    targets: [
        .target(
            name: "ClawlineCore",
            path: "Sources/ClawlineCore"
        ),
        .executableTarget(
            name: "Clawline",
            dependencies: ["ClawlineCore"],
            path: "Sources/Clawline"
        ),
        .executableTarget(
            name: "ClawlineCheck",
            dependencies: ["ClawlineCore"],
            path: "Sources/ClawlineCheck"
        ),
    ]
)
