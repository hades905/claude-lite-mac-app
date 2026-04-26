// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ClaudeLiteMacApp",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "ClaudeLiteCore",
            targets: ["ClaudeLiteCore"]
        ),
        .executable(
            name: "ClaudeLiteMacApp",
            targets: ["ClaudeLiteMacApp"]
        ),
        .executable(
            name: "ClaudeLitePackager",
            targets: ["ClaudeLitePackager"]
        )
    ],
    targets: [
        .target(
            name: "ClaudeLiteCore",
            path: "Sources/ClaudeLiteCore",
            resources: [
                .process("Rendering/Resources")
            ]
        ),
        .executableTarget(
            name: "ClaudeLiteMacApp",
            dependencies: ["ClaudeLiteCore"],
            path: "Sources/ClaudeLiteMacApp"
        ),
        .executableTarget(
            name: "ClaudeLitePackager",
            dependencies: ["ClaudeLiteCore"],
            path: "Sources/ClaudeLitePackager"
        )
    ]
)
