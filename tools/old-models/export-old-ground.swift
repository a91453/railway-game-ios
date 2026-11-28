import Foundation
@testable import GameCore
@testable import GamePresentation

// tools/old-models (decision 1042): three ground stations (tracks, platforms,
// canopies, platform props, building) as .m3dmodel for tools/model-look/shoot.mjs,
// in Japan (`<s|m|l>-after`) and as Taiwan's kit draws them (`-before`).
// Built as tools/model-look/export-station.sh builds its exporter:
//   swift build; bin="$(swift build --show-bin-path)"
//   swiftc -swift-version 6 -I "$bin" tools/old-models/export-old-ground.swift \
//       "$bin/GamePresentation.o" "$bin/GameCore.o" -o /tmp/export   # Linux: -I "$bin/Modules" and the .build/*.swift.o
//   /tmp/export OUTPUT_DIRECTORY
typealias Builder = Map3DScene.Builder
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let japan = GameWorld.newGame(anchor: GeoAnchor(latitudeDegrees: 33.5897, longitudeDegrees: 130.4207)!)

func line(z: Float, length: Float) -> [Map3DPoint] {
    stride(from: -length / 2, through: length / 2, by: 10).map { Map3DPoint($0, Map3DScene.railLift, z) }
}

struct Scene { let name: String; let tracks: [Float]; let platforms: [Builder.LaidPlatform]; let tier: Int; let expansion: StationExpansion?; let houseZ: Float }

let id = StationID(rawValue: 1), L: Float = 120
func side(_ track: Float, _ sign: Float) -> Builder.LaidPlatform {
    Builder.LaidPlatform(station: id, line: line(z: track, length: L), offset: sign * 3.2, width: 3.2, structure: .surface)
}
func half(_ track: Float, _ sign: Float) -> Builder.LaidPlatform {
    Builder.LaidPlatform(station: id, line: line(z: track, length: L), offset: sign * 3.55, width: 3.9, structure: .surface, island: true)
}
let scenes = [
    Scene(name: "s", tracks: [-2.5, 2.5], platforms: [side(-2.5, -1), side(2.5, 1)], tier: 2, expansion: nil, houseZ: 2.5 + 4.8 + 1),
    Scene(name: "m", tracks: [-5.5, 5.5, 14.5], platforms: [half(-5.5, 1), half(5.5, -1), side(14.5, 1)], tier: 1, expansion: nil,
          houseZ: 14.5 + 4.8 + 1),
    Scene(name: "l", tracks: [-5.5, 5.5, 14.5], platforms: [half(-5.5, 1), half(5.5, -1), side(14.5, 1)], tier: 1, expansion: .hall,
          houseZ: 14.5 + 4.8 + 1),
]

func write(_ mesh: Map3DMesh, _ name: String) throws {
    var tris: [[Map3DVertex]] = []
    for i in stride(from: 0, to: mesh.indices.count, by: 3) {
        tris.append((0..<3).map { mesh.vertices[Int(mesh.indices[i + $0])] })
    }
    let text = try JSONSerialization.data(withJSONObject: ["extras": ["assetId": name, "coordinateSystem": "metres; x front, y left, z up"]], options: [.sortedKeys])
    var data = Data("M3DM".utf8)
    func put16(_ n: UInt16) { data.append(UInt8(n & 255)); data.append(UInt8(n >> 8)) }
    func put32(_ n: UInt32) { for shift: UInt32 in [0, 8, 16, 24] { data.append(UInt8((n >> shift) & 255)) } }
    put16(1); put16(0); put32(UInt32(tris.count)); put32(UInt32(text.count)); data.append(text)
    data.append(contentsOf: [UInt8](repeating: 0, count: (4 - text.count % 4) % 4))
    for t in tris {
        put32(t.contains { $0.glows } ? 1 : 0)
        // Scene (x, y up, z right) to native (x front, y left, z up).
        for v in t { put32(v.x.bitPattern); put32((-v.z).bitPattern); put32(v.y.bitPattern); put32(v.color) }
    }
    try data.write(to: directory.appendingPathComponent(name + ".m3dmodel"), options: .atomic)
    print(name, tris.count)
}

for scene in scenes {
    for (label, world) in [("after", japan), ("before", GameWorld.newGame())] {
        var b = Builder(originX: 0, originY: 0, region: WorldRegion(minX: -64_000, minY: -64_000, maxX: 64_000, maxY: 64_000), world: world)
        b.state.platforms.laidPlatforms = scene.platforms
        b.state.stations.stationSystems[id] = "tra_sched"
        var mesh = Map3DMesh()
        // Ground, tracks and platforms as plain boxes.
        mesh.addBox(base: Map3DPoint(0, -0.1, 8), forward: Map3DPoint(1, 0, 0), length: 220, width: 80, height: 0.1,
                    top: Map3DPalette.plaza, side: Map3DPalette.plaza)
        for t in scene.tracks {
            mesh.addBox(base: Map3DPoint(0, 0, t), forward: Map3DPoint(1, 0, 0), length: 220, width: 3, height: Map3DScene.railLift,
                        top: Map3DPalette.ballast, side: Map3DPalette.ballast)
        }
        for p in scene.platforms {
            let z = p.line[0].z + p.offset
            mesh.addBox(base: Map3DPoint(0, 0, z), forward: Map3DPoint(1, 0, 0), length: L, width: p.width, height: Map3DScene.railLift + Builder.platformHeight,
                        top: Map3DPalette.platform, side: Map3DPalette.platform)
        }
        if label == "after" {
            for index in scene.platforms.indices { b.addOldCanopy(on: index, of: scene.platforms) }
        } else {
            for p in scene.platforms {
                var kit = StationKitBuilder()
                let width = min(p.width + 0.3, 7), count = Int((L * 0.6 / 8).rounded(.up)), step = L * 0.6 / Float(count)
                for i in 0..<count {
                    kit = StationKitBuilder()
                    kit.platformCanopy(length: step + 0.3, width: width, last: i == count - 1)
                    let x = -L * 0.3 + step * (Float(i) + 0.5)
                    mesh.append(kit.mesh, at: Map3DPoint(x, Map3DScene.railLift + Builder.platformHeight, p.line[0].z + p.offset), forward: Map3DPoint(1, 0, 0))
                }
            }
        }
        b.addPlatformProps()
        for m in Array(b.nearMeshes.values) + Array(b.closeMeshes.values) { mesh.append(m, at: .zero, forward: Map3DPoint(1, 0, 0)) }
        var kit = StationKitBuilder()
        kit.japanese = label == "after"
        let station = Map3DStationKit.Station(id: "game-1", name: "", system: "game", latitude: 0, longitude: 0, lines: [], profile: .regional,
                                              tier: scene.tier, seed: 1, planned: false, isLandmark: false)
        kit.genericHouse(station, expansion: scene.expansion)
        let bounds = kit.mesh.bounds!
        var house = Map3DMesh()
        house.append(kit.mesh, at: Map3DPoint(-bounds.min.x, 0, -(bounds.min.z + bounds.max.z) / 2), forward: Map3DPoint(1, 0, 0))
        // Kit x (away from the platforms) to scene +z, kit z to scene -x.
        mesh.append(house, at: Map3DPoint(0, 0, scene.houseZ), forward: Map3DPoint(0, 0, 1))
        try write(mesh, scene.name + "-" + label)
    }
}
