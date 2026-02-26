// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FlacConverter",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "FlacConverter", targets: ["FlacConverter"])
    ],
    targets: [
        .executableTarget(
            name: "FlacConverter"
        )
    ]
)