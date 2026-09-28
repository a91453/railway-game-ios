// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RailwayGame",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "GameCore", targets: ["GameCore"]),
        .library(name: "GamePresentation", targets: ["GamePresentation"]),
    ],
    targets: [
        .target(name: "GameCore"),
        .target(name: "GamePresentation", dependencies: ["GameCore"]),
        .testTarget(name: "GameCoreTests", dependencies: ["GameCore"]),
        .testTarget(name: "GamePresentationTests", dependencies: ["GamePresentation"]),
    ]
)
