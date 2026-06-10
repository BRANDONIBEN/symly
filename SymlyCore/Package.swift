// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SymlyCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "SymlyCore", targets: ["SymlyCore"]),
    ],
    targets: [
        .target(name: "SymlyCore"),
        .testTarget(
            name: "SymlyCoreTests",
            dependencies: ["SymlyCore"]
        ),
    ]
)
