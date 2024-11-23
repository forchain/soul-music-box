// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "SoulMusicBox",
    platforms: [
        .macOS(.v12)
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
    ],
    targets: [
        .target(
            name: "SoulMusicBox",
            dependencies: ["Yams"]
        ),
        .testTarget(
            name: "SoulMusicBoxTests",
            dependencies: ["SoulMusicBox"]
        ),
    ]
) 