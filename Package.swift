// swift-tools-version: 6.0
import PackageDescription

// Decision 544: on Linux (CI and the cloud sessions) GameCore and its tests
// build with -O, even in the debug configuration `swift build` and
// `swift test` use. Debug code ran the long simulations and the property
// campaigns' reference models about ten times slower; the rest stays
// unoptimized, as -O there costs more build time than it saves. -O keeps
// every check the tests rely on (preconditions, overflow traps, XCTest's
// assertions; the package has no assert or #if DEBUG), and the shipped app
// already runs an optimized GameCore. Xcode builds on macOS are unchanged.
#if os(Linux)
let optimized: [SwiftSetting] = [.unsafeFlags(["-O"])]
#else
let optimized: [SwiftSetting] = []
#endif

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
        .target(name: "GameCore", swiftSettings: optimized),
        .target(name: "GamePresentation", dependencies: ["GameCore"]),
        // Decision 260: the game with no screen, for tools (`swift run GameSim --help`).
        .executableTarget(name: "GameSim", dependencies: ["GamePresentation"]),
        .testTarget(name: "GameCoreTests", dependencies: ["GameCore"], swiftSettings: optimized),
        .testTarget(name: "GamePresentationTests", dependencies: ["GamePresentation"]),
    ]
)
