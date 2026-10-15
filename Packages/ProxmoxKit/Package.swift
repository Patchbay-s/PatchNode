// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "ProxmoxKit",
    platforms: [.iOS(.v27), .macOS(.v27)],
    products: [
        .library(name: "ProxmoxKit", targets: ["ProxmoxKit"])
    ],
    dependencies: [
        .package(path: "../PatchNodeCore")
    ],
    targets: [
        .target(
            name: "ProxmoxKit",
            dependencies: ["PatchNodeCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "ProxmoxKitTests",
            dependencies: ["ProxmoxKit", "PatchNodeCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
