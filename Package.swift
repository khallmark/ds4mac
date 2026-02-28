// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DS4Mac",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DS4Protocol", targets: ["DS4Protocol"]),
        .executable(name: "DS4Tool", targets: ["DS4Tool"]),
    ],
    targets: [
        .target(
            name: "DS4Protocol",
            path: "Sources/DS4Protocol"
        ),
        .executableTarget(
            name: "DS4Tool",
            dependencies: ["DS4Protocol"],
            path: "Sources/DS4Tool",
            linkerSettings: [
                .linkedFramework("IOKit"),
            ]
        ),
        .testTarget(
            name: "DS4ProtocolTests",
            dependencies: ["DS4Protocol"],
            path: "Tests/DS4ProtocolTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
