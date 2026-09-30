// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RailwayWasmProbe",
    dependencies: [.package(name: "RailwayGame", path: "../..")],
    targets: [
        .executableTarget(
            name: "RailwayWasmProbe",
            dependencies: [.product(name: "GameCore", package: "RailwayGame")],
            path: "Generated"
        ),
    ]
)
