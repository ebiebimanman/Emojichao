// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Emojichao",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Emojichao", targets: ["EmojiShortcut"]),
        .executable(name: "EmojiCuration", targets: ["EmojiCuration"])
    ],
    dependencies: [
        // The portable catalog/scoring/shortcode-search logic shared with
        // the iOS keyboard extension. Kept as its own package (rather than a
        // target here) so it stays free of this package's AppKit-only
        // targets — Xcode needs to resolve it standalone for an iOS target.
        .package(path: "EmojiCatalogCore")
    ],
    targets: [
        .executableTarget(
            name: "EmojiShortcut",
            dependencies: [.product(name: "EmojiCatalogCore", package: "EmojiCatalogCore")],
            path: "AppSources/EmojiShortcut",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "EmojiCuration",
            path: "AppSources/EmojiCuration"
        ),
        .testTarget(
            name: "EmojiShortcutTests",
            dependencies: [
                "EmojiShortcut",
                .product(name: "EmojiCatalogCore", package: "EmojiCatalogCore")
            ]
        )
    ]
)
