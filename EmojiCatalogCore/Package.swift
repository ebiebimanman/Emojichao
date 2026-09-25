// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EmojiCatalogCore",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "EmojiCatalogCore", targets: ["EmojiCatalogCore"])
    ],
    targets: [
        .target(
            name: "EmojiCatalogCore",
            resources: [.process("Resources")]
        )
    ]
)
