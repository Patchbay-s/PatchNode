// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "SecurityKit",
    platforms: [.iOS(.v27), .macOS(.v27)],
    products: [
        .library(name: "SecurityKit", targets: ["SecurityKit"])
    ],
    dependencies: [
        .package(path: "../PatchNodeCore")
    ],
    targets: [
        .target(
            name: "SecurityKit",
            dependencies: ["PatchNodeCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "SecurityKitTests",
            dependencies: ["SecurityKit", "PatchNodeCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
