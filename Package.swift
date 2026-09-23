// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Emojichao",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Emojichao", targets: ["EmojiShortcut"]),
        .executable(name: "EmojiCuration", targets: ["EmojiCuration"])
    ],
    targets: [
        .executableTarget(
            name: "EmojiShortcut",
            path: "AppSources/EmojiShortcut",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "EmojiCuration",
            path: "AppSources/EmojiCuration"
        ),
        .testTarget(name: "EmojiShortcutTests", dependencies: ["EmojiShortcut"])
    ]
)
