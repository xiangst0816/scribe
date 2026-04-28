// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Scribe",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.6.4"),
    ],
    targets: [
        // llama.cpp consumed as a binary xcframework. The arm64 macOS slice is
        // ~9 MB linked into the .app; SwiftPM strips dSYMs at integration time.
        // Pinned to a specific release so Sparkle delta updates and CI builds
        // are reproducible.
        .binaryTarget(
            name: "llama",
            url: "https://github.com/ggml-org/llama.cpp/releases/download/b8943/llama-b8943-xcframework.zip",
            checksum: "96ad022efc1973aba8c0ee1d5e0666db3c3692374895f1c7b27bfe4275b55f63"
        ),
        // Library holding all of the app's logic so tests can `@testable import`
        // it without `main.swift` trying to run NSApplication on the test bundle.
        .target(
            name: "ScribeCore",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
                "llama",
            ],
            path: "Sources/Scribe"
        ),
        .executableTarget(
            name: "Scribe",
            dependencies: ["ScribeCore"],
            path: "Sources/ScribeApp",
            linkerSettings: [
                // Without this, Sparkle.framework / llama.framework are invisible
                // to dyld at runtime because SwiftPM's default rpath only points
                // beside the binary.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@loader_path/../Frameworks"]),
            ]
        ),
        .testTarget(
            name: "ScribeCoreTests",
            dependencies: ["ScribeCore"],
            path: "Tests/ScribeCoreTests"
        ),
        // Local-only eval harness for the polish prompt. Not part of the
        // shipped app or CI; remove after evaluation work is done.
        .executableTarget(
            name: "PolishEval",
            dependencies: ["ScribeCore"],
            path: "Tools/PolishEval",
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@loader_path/../Frameworks"]),
            ]
        ),
    ]
)
