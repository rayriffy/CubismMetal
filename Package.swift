// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CubismMetal",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CubismMetal", targets: ["CubismMetalApp"]),
        .executable(name: "CubismMetalVerification", targets: ["CubismMetalVerification"]),
    ],
    targets: [
        .target(
            name: "CubismMetalKit",
            path: "Sources/CubismMetalKit",
            resources: [.copy("Shaders")],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("QuartzCore"),
            ]
        ),
        .executableTarget(
            name: "CubismMetalApp",
            dependencies: ["CubismMetalKit"],
            path: "Sources/CubismMetalApp"
        ),
        .executableTarget(
            name: "CubismMetalVerification",
            dependencies: ["CubismMetalKit"],
            path: "Sources/CubismMetalVerification"
        ),
        .testTarget(
            name: "CubismMetalKitTests",
            dependencies: ["CubismMetalKit"],
            path: "Tests/CubismMetalKitTests"
        ),
    ]
)
