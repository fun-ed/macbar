// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "macbar",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "macbar",
            path: "Sources/macbar"
        )
    ]
)