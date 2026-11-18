// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CrossoverApp",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "CrossoverApp",
            targets: ["CrossoverApp"]
        )
    ],
    targets: [
        .target(
            name: "YouTubeModule",
            path: "Sources/YouTubeModule",
            resources: [
                .process("Assets.xcassets"),
                .process("Resources")
            ]
        ),
        .target(
            name: "NetflixModule",
            path: "Sources/NetflixModule",
            resources: [
                .process("Resources")
            ]
        ),
        .target(
            name: "SpotifyModule",
            path: "Sources/SpotifyModule",
            resources: [
                .process("Resources")
            ]
        ),
        .target(
            name: "CrossoverApp",
            dependencies: [
                "YouTubeModule",
                "NetflixModule",
                "SpotifyModule"
            ],
            path: "Sources/CrossoverApp",
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
