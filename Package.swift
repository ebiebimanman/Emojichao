// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Emojichao",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .executable(name: "Emojichao", targets: ["EmojiShortcut"]),
        .executable(name: "EmojiCuration", targets: ["EmojiCuration"]),
        .library(name: "EmojiCatalogCore", targets: ["EmojiCatalogCore"])
    ],
    targets: [
        // Portable emoji lookup logic (catalog, scoring, shortcode-search
        // policy) shared between the macOS app and the iOS keyboard
        // extension. Foundation-only, no AppKit/UIKit dependency.
        .target(
            name: "EmojiCatalogCore",
            path: "AppSources/EmojiCatalogCore",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "EmojiShortcut",
            dependencies: ["EmojiCatalogCore"],
            path: "AppSources/EmojiShortcut",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "EmojiCuration",
            path: "AppSources/EmojiCuration"
        ),
        .testTarget(
            name: "EmojiShortcutTests",
            dependencies: ["EmojiShortcut", "EmojiCatalogCore"]
        )
    ]
)
