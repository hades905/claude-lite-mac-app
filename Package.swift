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
            name: "ClaudeLiteSmoke",
            targets: ["ClaudeLiteSmoke"]
        ),
        .executable(
            name: "ClaudeLitePackager",
            targets: ["ClaudeLitePackager"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-testing.git", exact: "6.2.1")
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
            name: "ClaudeLiteSmoke",
            dependencies: ["ClaudeLiteCore"],
            path: "Sources/ClaudeLiteSmoke"
        ),
        .executableTarget(
            name: "ClaudeLitePackager",
            dependencies: ["ClaudeLiteCore"],
            path: "Sources/ClaudeLitePackager"
        ),
        .testTarget(
            name: "ClaudeLiteCoreTests",
            dependencies: [
                "ClaudeLiteCore",
                .product(name: "Testing", package: "swift-testing")
            ],
            path: "Tests/ClaudeLiteCoreTests"
        ),
        .testTarget(
            name: "ClaudeLiteMacAppTests",
            dependencies: [
                "ClaudeLiteMacApp",
                "ClaudeLiteCore",
                .product(name: "Testing", package: "swift-testing")
            ],
            path: "Tests/ClaudeLiteMacAppTests"
        )
    ]
)
