// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "TailscaleKit",
    platforms: [.iOS(.v27), .macOS(.v27)],
    products: [
        .library(name: "TailscaleKit", targets: ["TailscaleKit"])
    ],
    dependencies: [
        .package(path: "../PatchNodeCore")
    ],
    targets: [
        .target(
            name: "TailscaleKit",
            dependencies: ["PatchNodeCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "TailscaleKitTests",
            dependencies: ["TailscaleKit", "PatchNodeCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
