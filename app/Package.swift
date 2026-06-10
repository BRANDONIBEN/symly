// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Symly",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(path: "../SymlyCore"),
    ],
    targets: [
        .executableTarget(
            name: "Symly",
            dependencies: [
                .product(name: "SymlyCore", package: "SymlyCore"),
            ]
        ),
    ]
)
