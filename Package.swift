// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "WallpaperEngineMac",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "WallpaperEngineCore",
            targets: ["WallpaperEngineCore"]
        ),
        .executable(
            name: "WallpaperEngineMac",
            targets: ["WallpaperEngineMac"]
        ),
        .executable(
            name: "WallpaperEngineSmokeTests",
            targets: ["WallpaperEngineSmokeTests"]
        )
    ],
    targets: [
        .target(
            name: "WallpaperEngineCore"
        ),
        .executableTarget(
            name: "WallpaperEngineMac",
            dependencies: ["WallpaperEngineCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("ImageIO"),
                .linkedFramework("IOKit"),
                .linkedFramework("QuartzCore")
            ]
        ),
        .executableTarget(
            name: "WallpaperEngineSmokeTests",
            dependencies: ["WallpaperEngineCore"]
        )
    ]
)
