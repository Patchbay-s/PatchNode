// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "HomeServicesKit",
    platforms: [.iOS(.v27), .macOS(.v27)],
    products: [
        .library(name: "HomeServicesKit", targets: ["HomeServicesKit"])
    ],
    dependencies: [
        .package(path: "../PatchNodeCore")
    ],
    targets: [
        .target(
            name: "HomeServicesKit",
            dependencies: ["PatchNodeCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "HomeServicesKitTests",
            dependencies: ["HomeServicesKit", "PatchNodeCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
