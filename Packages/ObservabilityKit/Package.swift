// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "ObservabilityKit",
    platforms: [.iOS(.v27), .macOS(.v27)],
    products: [
        .library(name: "ObservabilityKit", targets: ["ObservabilityKit"])
    ],
    dependencies: [
        .package(path: "../PatchNodeCore")
    ],
    targets: [
        .target(
            name: "ObservabilityKit",
            dependencies: ["PatchNodeCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "ObservabilityKitTests",
            dependencies: ["ObservabilityKit", "PatchNodeCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
