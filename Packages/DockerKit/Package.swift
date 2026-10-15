// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "DockerKit",
    platforms: [.iOS(.v27), .macOS(.v27)],
    products: [
        .library(name: "DockerKit", targets: ["DockerKit"])
    ],
    dependencies: [
        .package(path: "../PatchNodeCore")
    ],
    targets: [
        .target(
            name: "DockerKit",
            dependencies: ["PatchNodeCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "DockerKitTests",
            dependencies: ["DockerKit", "PatchNodeCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
