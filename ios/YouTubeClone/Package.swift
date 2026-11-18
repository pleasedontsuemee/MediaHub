// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "YouTubeClone",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "YouTubeClone",
            targets: ["YouTubeClone"]
        ),
    ],
    targets: [
        .target(
            name: "YouTubeClone",
            path: "YouTubeClone",
            exclude: [
                "Info.plist"
            ],
            resources: [
                .process("Assets.xcassets"),
                .process("Resources")
            ]
        ),
    ]
)
