// swift-tools-version: 6.0
import PackageDescription

// Decision 544: on Linux (CI and the cloud sessions) GameCore and its tests
// build with -O, even in the debug configuration `swift build` and
// `swift test` use. Debug code ran the long simulations and the property
// campaigns' reference models about ten times slower; GamePresentation
// stays unoptimized there, as -O costs it more build time than it saves.
// -O keeps every check the tests rely on (preconditions, overflow traps,
// XCTest's assertions; the package has no assert or #if DEBUG).
//
// Decision 624: Xcode's builds of the app for iOS optimize GameCore and
// GamePresentation in the Debug configuration too (the app references
// this package by path, so its unsafe flags apply). The Debug app on the
// Simulator, which the UI tests and the website's screenshots run, opened
// a demo at 07:00 and stood still for seconds; Release was already -O.
let core: [SwiftSetting] = [.unsafeFlags(["-O"], .when(platforms: [.linux, .iOS]))]
let presentation: [SwiftSetting] = [.unsafeFlags(["-O"], .when(platforms: [.iOS]))]
let coreTests: [SwiftSetting] = [.unsafeFlags(["-O"], .when(platforms: [.linux]))]

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
        .target(name: "GameCore", swiftSettings: core),
        .target(name: "GamePresentation", dependencies: ["GameCore"], swiftSettings: presentation),
        // Decision 260: the game with no screen, for tools (`swift run GameSim --help`).
        .executableTarget(name: "GameSim", dependencies: ["GamePresentation"]),
        .testTarget(name: "GameCoreTests", dependencies: ["GameCore"], swiftSettings: coreTests),
        .testTarget(name: "GamePresentationTests", dependencies: ["GamePresentation"]),
    ]
)
