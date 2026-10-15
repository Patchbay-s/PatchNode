// swift-tools-version: 6.4
import PackageDescription

// The terminal shared by Proxmox consoles and SSH sessions (SwiftTerm).
// Third-party code is an explicit exception to "no external dependency"
// (CLAUDE.md): SwiftTerm is pinned with `exact:`; swift-argument-parser, which
// its manifest declares for its command-line tools only, by the committed
// Package.resolved of PatchNode.xcodeproj. Both are listed in Settings › About. SwiftTerm 1.10.1: no build-tool plugin and no
// Metal shader (newer versions need Xcode's separate Metal toolchain).
let package = Package(
    name: "TerminalKit",
    platforms: [.iOS(.v27), .macOS(.v27)],
    products: [
        .library(name: "TerminalKit", targets: ["TerminalKit"])
    ],
    dependencies: [
        .package(path: "../PatchNodeCore"),
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.10.1"),
    ],
    targets: [
        .target(
            name: "TerminalKit",
            dependencies: [
                "PatchNodeCore",
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "TerminalKitTests",
            dependencies: ["TerminalKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
