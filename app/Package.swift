// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Symly",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(path: "../MediaOrganizerCore"),
    ],
    targets: [
        .executableTarget(
            name: "Symly",
            dependencies: [
                .product(name: "MediaOrganizerCore", package: "MediaOrganizerCore"),
            ]
        ),
    ]
)
