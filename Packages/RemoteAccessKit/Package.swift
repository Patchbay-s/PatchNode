// swift-tools-version: 6.4
import PackageDescription

// SSH (Apple's SwiftNIO SSH), Proxmox consoles and Docker Compose over SSH.
// Third-party code is an explicit exception to "no external dependency"
// (CLAUDE.md): direct dependencies are pinned with `exact:`; their own
// dependencies (swift-atomics, swift-collections, swift-system, swift-asn1)
// are pinned by the committed Package.resolved of PatchNode.xcodeproj. All are
// listed in Settings › About.
let package = Package(
    name: "RemoteAccessKit",
    platforms: [.iOS(.v27), .macOS(.v27)],
    products: [
        .library(name: "RemoteAccessKit", targets: ["RemoteAccessKit"])
    ],
    dependencies: [
        .package(path: "../PatchNodeCore"),
        .package(path: "../ProxmoxKit"),
        .package(path: "../DockerKit"),
        .package(url: "https://github.com/apple/swift-nio-ssh.git", exact: "0.15.0"),
        .package(url: "https://github.com/apple/swift-nio.git", exact: "2.103.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", exact: "4.5.2"),
    ],
    targets: [
        .target(
            name: "RemoteAccessKit",
            dependencies: [
                "PatchNodeCore",
                "ProxmoxKit",
                "DockerKit",
                .product(name: "NIOSSH", package: "swift-nio-ssh"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "Crypto", package: "swift-crypto"),
            ],
            // noVNC 1.7.0, embedded unmodified (folder kept: ES module paths).
            resources: [.copy("Resources/noVNC")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "RemoteAccessKitTests",
            dependencies: [
                "RemoteAccessKit", "PatchNodeCore", "ProxmoxKit", "DockerKit",
                // An in-process SSH server for the client's tests.
                .product(name: "NIOSSH", package: "swift-nio-ssh"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "Crypto", package: "swift-crypto"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
