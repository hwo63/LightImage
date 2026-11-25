// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LightImage",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "LightImage", targets: ["LightImage"])],
    targets: [
        .target(name: "LightImageCore"),
        .executableTarget(name: "LightImage", dependencies: ["LightImageCore"]),
        .executableTarget(name: "LightImageDiagnostics", dependencies: ["LightImageCore"]),
        .testTarget(name: "LightImageCoreTests", dependencies: ["LightImageCore"])
    ]
)
