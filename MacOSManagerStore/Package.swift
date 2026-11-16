// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacOSManagerStoreCore",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "MacOSManagerStoreCore", targets: ["MacOSManagerStoreCore"]),
    ],
    targets: [
        .target(
            name: "MacOSManagerStoreCore",
            path: "Sources/MacOSManagerStoreCore",
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "MacOSManagerStoreCoreTests",
            dependencies: ["MacOSManagerStoreCore"],
            path: "Tests/MacOSManagerStoreCoreTests"
        ),
    ]
)
