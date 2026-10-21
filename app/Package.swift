// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "WinebuildManager",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "WinebuildManager", targets: ["WinebuildManager"]),
    ],
    targets: [
        // Everything that doesn't need a UI: bottle discovery, .lnk/PE/registry parsing, wrun command lines.
        .target(name: "WineKit", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(
            name: "WinebuildManager",
            dependencies: ["WineKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "WineKitTests",
            dependencies: ["WineKit"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
