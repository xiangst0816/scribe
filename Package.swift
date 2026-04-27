// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Scribe",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "0.18.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.6.4"),
    ],
    targets: [
        .executableTarget(
            name: "Scribe",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/Scribe"
        )
    ]
)
