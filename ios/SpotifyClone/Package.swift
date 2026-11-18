// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SpotifyClone",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "SpotifyClone",
            targets: ["SpotifyClone"]
        )
    ],
    targets: [
        .target(
            name: "SpotifyClone",
            path: "SpotifyClone",
            exclude: [
                "Info.plist",
                "Assets.xcassets"
            ],
            resources: [
                .process("Resources")
            ]
        )
    ]
)
