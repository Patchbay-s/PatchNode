// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "PatchNodeCore",
    platforms: [.iOS(.v27), .macOS(.v27)],
    products: [
        .library(name: "PatchNodeCore", targets: ["PatchNodeCore"])
    ],
    targets: [
        .target(
            name: "PatchNodeCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "PatchNodeCoreTests",
            dependencies: ["PatchNodeCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
