// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Hushclip",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Hushclip", targets: ["Hushclip"]),
    ],
    targets: [
        // Pure logic: categorization, model, encryption, keychain. Unit-tested.
        .target(name: "HushclipCore", path: "Sources/HushclipCore"),
        // The menu bar app: pasteboard monitor, hotkey, overlay UI.
        .executableTarget(
            name: "Hushclip",
            dependencies: ["HushclipCore"],
            path: "Sources/Hushclip"
        ),
        .testTarget(
            name: "HushclipCoreTests",
            dependencies: ["HushclipCore"],
            path: "Tests/HushclipCoreTests"
        ),
    ]
)
