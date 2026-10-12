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
            dependencies: ["AppAudioRT"],
            path: "Sources/macbar"
        ),
        .target(
            name: "AppAudioRT",
            path: "Sources/AppAudioRT",
            publicHeadersPath: "include"
        ),
        .testTarget(
            name: "macbarTests",
            dependencies: ["macbar", "AppAudioRT"],
            path: "Tests/macbarTests"
        )
    ]
)