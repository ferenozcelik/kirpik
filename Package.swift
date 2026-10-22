// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Kirpik",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Kirpik",
            path: "Sources/Kirpik",
            linkerSettings: [.linkedFramework("Carbon")]
        )
    ]
)
