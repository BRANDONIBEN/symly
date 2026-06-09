// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MediaOrganizerCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MediaOrganizerCore", targets: ["MediaOrganizerCore"]),
    ],
    targets: [
        .target(name: "MediaOrganizerCore"),
        .testTarget(
            name: "MediaOrganizerCoreTests",
            dependencies: ["MediaOrganizerCore"]
        ),
    ]
)
