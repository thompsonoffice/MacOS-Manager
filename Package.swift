// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacOSManager",
    products: [
        .library(name: "MacOSManagerCore", targets: ["MacOSManagerCore"]),
    ],
    targets: [
        .target(
            name: "MacOSManagerCore",
            path: "Sources/MacOSManagerCore",
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "MacOSManagerCoreTests",
            dependencies: ["MacOSManagerCore"],
            path: "Tests/MacOSManagerCoreTests"
        ),
    ]
)
