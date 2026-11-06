// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Clipster",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Clipster", targets: ["Clipster"]),
    ],
    targets: [
        // Pure logic: categorization, model, encryption, keychain. Unit-tested.
        .target(name: "ClipsterCore", path: "Sources/ClipsterCore"),
        // The menu bar app: pasteboard monitor, hotkey, overlay UI.
        .executableTarget(
            name: "Clipster",
            dependencies: ["ClipsterCore"],
            path: "Sources/Clipster"
        ),
        .testTarget(
            name: "ClipsterCoreTests",
            dependencies: ["ClipsterCore"],
            path: "Tests/ClipsterCoreTests"
        ),
    ]
)
