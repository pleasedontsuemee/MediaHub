// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NetflixClone",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "NetflixClone",
            targets: ["NetflixClone"]
        )
    ],
    targets: [
        .target(
            name: "NetflixClone",
            path: "NetflixClone",
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
