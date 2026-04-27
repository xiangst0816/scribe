// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Scribe",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.6.4"),
    ],
    targets: [
        // Library holding all of the app's logic so tests can `@testable import`
        // it without `main.swift` trying to run NSApplication on the test bundle.
        .target(
            name: "ScribeCore",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/Scribe"
        ),
        .executableTarget(
            name: "Scribe",
            dependencies: ["ScribeCore"],
            path: "Sources/ScribeApp",
            linkerSettings: [
                // Without this, Sparkle.framework is invisible to dyld at runtime
                // because SwiftPM's default rpath only points beside the binary.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@loader_path/../Frameworks"]),
            ]
        ),
        .testTarget(
            name: "ScribeCoreTests",
            dependencies: ["ScribeCore"],
            path: "Tests/ScribeCoreTests"
        ),
    ]
)
