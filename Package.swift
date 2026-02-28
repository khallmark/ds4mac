// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DS4Mac",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DS4Protocol", targets: ["DS4Protocol"]),
        .library(name: "DS4Transport", targets: ["DS4Transport"]),
        .executable(name: "DS4Tool", targets: ["DS4Tool"]),
        .executable(name: "DS4Mac", targets: ["DS4Mac"]),
    ],
    targets: [
        .target( 
            name: "DS4Protocol",
            path: "Sources/DS4Protocol"
        ),
        .target(
            name: "DS4Transport",
            dependencies: ["DS4Protocol"],
            path: "Sources/DS4Transport",
            linkerSettings: [
                .linkedFramework("IOKit"),
            ]
        ),
        .executableTarget(
            name: "DS4Tool",
            dependencies: ["DS4Protocol", "DS4Transport"],
            path: "Sources/DS4Tool",
            linkerSettings: [
                .linkedFramework("IOKit"),
            ]
        ),
        .executableTarget(
            name: "DS4Mac",
            dependencies: ["DS4Protocol", "DS4Transport"],
            path: "Sources/DS4Mac",
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
        .testTarget(
            name: "DS4TransportTests",
            dependencies: ["DS4Transport", "DS4Protocol"],
            path: "Tests/DS4TransportTests"
        ),
    ]
)
