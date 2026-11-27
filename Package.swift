// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LightImage",
    defaultLocalization: "vi",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "LightImage", targets: ["LightImage"]),
        .executable(name: "LightImageInstaller", targets: ["LightImageInstaller"])
    ],
    targets: [
        .target(name: "LightImageCore", resources: [.process("Resources")]),
        .executableTarget(name: "LightImage", dependencies: ["LightImageCore"]),
        .executableTarget(name: "LightImageInstaller"),
        .executableTarget(name: "LightImageDiagnostics", dependencies: ["LightImageCore"]),
        .testTarget(name: "LightImageCoreTests", dependencies: ["LightImageCore"]),
        .testTarget(name: "LightImageTests", dependencies: ["LightImage", "LightImageCore"]),
        .testTarget(name: "LightImageUpdateTests", dependencies: ["LightImage"])
    ]
)
