import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 860: the underground stations' platforms drawn solid, in a
/// box along the station in place of the round bore, the old version's
/// island module down an island.
@MainActor
final class UndergroundStationsTests: XCTestCase {
    typealias Stations = Map3DUndergroundStations
    private static let metre = Double(WorldCoordinate.unitsPerMetre)

    /// Flat ground at 0 m; a track from x = 32 m down a tunnel to 15 m
    /// under it at 480 m and on, level, to 960 m; beside its level part,
    /// 10 m to the south (+y), a second tunnel track. With `island`, a
    /// station whose two platforms (520 m to 740 m) face each other across
    /// an island; without, one side platform on the first track.
    private func world(island: Bool) throws -> GameWorld {
        var world = try GameWorld(bounds: WorldBounds(width: 81_920, height: 32_768),
                                  economy: GameEconomy(balance: 100_000_000, costs: testCosts), clock: GameClock(speed: .normal))
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 2_048, y: 16_384))
        let portal = try world.buildTrackNode(at: WorldCoordinate(x: 6_144, y: 16_384))
        let down = try world.buildTrackNode(at: WorldCoordinate(x: 30_720, y: 16_384, z: -960))
        let end = try world.buildTrackNode(at: WorldCoordinate(x: 61_440, y: 16_384, z: -960))
        try world.buildTrackEdge(from: a, to: portal)
        try world.buildTrackEdge(from: portal, to: down, structure: .tunnel)
        try world.buildTrackEdge(from: down, to: end, structure: .tunnel)
        let station = try world.buildStation(named: "Deep", at: PlanPoint(x: 40_000, y: 16_700))
        try world.addTrackPlatform(station.id, on: .edge(3), from: 40 * 64, to: 260 * 64)
        if island {
            let besideA = try world.buildTrackNode(at: WorldCoordinate(x: 30_720, y: 17_024, z: -960))
            let besideB = try world.buildTrackNode(at: WorldCoordinate(x: 61_440, y: 17_024, z: -960))
            try world.buildTrackEdge(from: besideA, to: besideB, structure: .tunnel)
            try world.addTrackPlatform(station.id, on: .edge(4), from: 40 * 64, to: 260 * 64)
        }
        return world
    }

    private func stations(_ world: GameWorld) -> (stations: Stations, scene: Map3DScene) {
        let scene = Map3DScene(world: world)
        return (Stations(world.railwaySnapshot(), point: scene.point, cover: scene.trackCover), scene)
    }

    /// One platform, beside its track; one box round it, reaching from its
    /// bore's wall to past the platform's back and on past both its ends,
    /// open at both ends where the track runs on; the bore cut away along
    /// it and nowhere else.
    func testASidePlatformsStationIsABoxWithTheBoreOpeningIntoIt() throws {
        let (stations, _) = stations(try world(island: false))
        XCTAssertEqual(stations.platforms.count, 1)
        let platform = try XCTUnwrap(stations.platforms.first)
        XCTAssertFalse(platform.island)
        XCTAssertEqual(platform.width, Map3DScene.Builder.platformWidth)
        XCTAssertEqual(stations.boxes.count, 1)
        let box = try XCTUnwrap(stations.boxes.first)
        let reach = Map3DScene.Builder.platformEdge + platform.width
        XCTAssertEqual(box.left, -reach - Stations.wallGap, accuracy: 0.01, "the wall behind the platform")
        XCTAssertEqual(box.right, Map3DScene.Builder.boreHalfWidth, accuracy: 0.01, "the bore's wall on the other side")
        XCTAssertEqual(Stations.length(box.path), 220 + 2 * Stations.endRoom, accuracy: 0.5)
        XCTAssertEqual(box.openings.start.count, 1, "the track comes in at one end")
        XCTAssertEqual(box.openings.end.count, 1, "and goes on at the other")
        XCTAssertEqual(box.openings.start[0], 0, accuracy: 0.05)

        // Its track run on 100 m past each end loses its bore along the
        // box and keeps it either side.
        let shifted = Stations.extend(platform.line, before: 100, after: 100)
        let pieces = stations.outside(shifted)
        XCTAssertEqual(pieces.count, 2)
        let kept = pieces.map(Stations.length).reduce(0, +)
        XCTAssertEqual(kept, Stations.length(shifted) - Stations.length(box.path), accuracy: 0.5)
        for piece in pieces {
            for point in piece.dropFirst().dropLast() {
                let at = try XCTUnwrap(Stations.locate(point, along: box.path, beyond: 1_000))
                XCTAssertTrue(at.along < 0 || at.along > Stations.length(box.path), "no bore inside the box")
            }
        }
        // A track at another level runs on in its bore under it.
        XCTAssertEqual(stations.outside(shifted.map { $0 - Map3DPoint(0, 12, 0) }).count, 1)
    }

    /// Two platforms across an island: one island (two halves) between
    /// the two tracks, one box from bore wall to bore wall, the old
    /// version's module along the island, and two openings each end.
    func testAnIslandStationHasOneBoxAndTheOldModulesAlongIt() throws {
        let (stations, scene) = stations(try world(island: true))
        XCTAssertEqual(stations.platforms.count, 2)
        XCTAssertTrue(stations.platforms.allSatisfy(\.island))
        for platform in stations.platforms {
            XCTAssertEqual(platform.width, 5 - Map3DScene.Builder.platformEdge, accuracy: 0.05, "half the island")
        }
        XCTAssertEqual(stations.boxes.count, 1)
        let box = try XCTUnwrap(stations.boxes.first)
        XCTAssertEqual(box.right - box.left, 10 + 2 * Map3DScene.Builder.boreHalfWidth, accuracy: 0.05)
        XCTAssertEqual(box.openings.start.count, 2, "both tracks run on")
        XCTAssertEqual(box.openings.end.count, 2)
        XCTAssertEqual(Map3DOldIslandModule.modules(along: 220).count, 5)

        // Drawn, in the base mesh (decision 394's cab view underground
        // keeps it): the platform's top at its height, the ceiling's lamps
        // lit, and on the island's middle, between the platform's top and
        // the ceiling, the old module's furniture.
        let rails = stations.platforms[0].line[0].y
        let middle = box.path[box.path.count / 2], across = Map3DMesh.acrossDirections(box.path)[box.path.count / 2]
        let island = (box.left + box.right) / 2
        var paving = 0, lamps = 0, furniture = 0
        for chunk in scene.chunks {
            for index in chunk.mesh.indices.prefix(chunk.baseIndexCount) {
                let vertex = chunk.mesh.vertices[Int(index)]
                let point = Map3DPoint(vertex.x, vertex.y, vertex.z), height = vertex.y - rails
                guard abs(height) < 8, abs((point - middle).dot(across) - island) < 1.3 else { continue }
                if abs(height - Map3DScene.Builder.platformHeight) < 0.02 { paving += 1 }
                if vertex.glows, height > 5 { lamps += 1 }
                if height > Map3DScene.Builder.platformHeight + 0.1, height < Stations.ceiling - 0.2, !vertex.glows { furniture += 1 }
            }
        }
        XCTAssertGreaterThan(paving, 0, "the island drawn")
        XCTAssertGreaterThan(lamps, 0, "the ceiling's lamps")
        XCTAssertGreaterThan(furniture, 0, "the old module's furniture")
    }

    /// The old version's module: its fourteen parts every 40 m, so many
    /// whole modules as the island holds, each part within the island's
    /// width (the hung signs over its tracks) and under the ceiling.
    func testTheOldModuleScalesToTheIsland() throws {
        XCTAssertEqual(Map3DOldIslandModule.parts.count, 14)
        XCTAssertEqual(Map3DOldIslandModule.modules(along: 39).count, 0)
        XCTAssertEqual(Map3DOldIslandModule.modules(along: 125).count, 3)
        XCTAssertEqual(Map3DOldIslandModule.modules(along: 125).start, 2.5)
        var mesh = Map3DMesh()
        let width: Float = 4, headroom = Stations.ceiling - Map3DScene.Builder.platformHeight
        Map3DScene.Builder.addIslandModules(&mesh, from: 0, to: 80, width: width, headroom: headroom) { along in
            (Map3DPoint(along, 0, 0), Map3DPoint(1, 0, 0), Map3DPoint(0, 0, 1))
        }
        XCTAssertFalse(mesh.vertices.isEmpty)
        XCTAssertLessThanOrEqual(mesh.vertices.map(\.y).max() ?? 99, headroom + 0.001, "under the ceiling")
        XCTAssertGreaterThanOrEqual(mesh.vertices.map(\.y).min() ?? -1, 0, "on the platform")
        let reach = 4.8 * width / Map3DOldIslandModule.width
        XCTAssertLessThanOrEqual(mesh.vertices.map { abs($0.z) }.max() ?? 99, reach + 0.001)
        XCTAssertLessThanOrEqual(mesh.vertices.map(\.x).max() ?? 99, 80)
    }

    /// No underground station, nothing: the bore whole.
    func testNoStationLeavesTheBoreWhole() {
        let empty = Stations()
        let line = [Map3DPoint(0, -10, 0), Map3DPoint(100, -10, 0)]
        XCTAssertEqual(empty.outside(line), [line])
    }

    /// `UNDERGROUND_PREVIEW=<file.json>`: the island station's meshes
    /// round its box, for the decision's preview
    /// (`tools/underground-station/preview.py` draws them).
    func testWriteThePreviewsMeshes() throws {
        guard let out = ProcessInfo.processInfo.environment["UNDERGROUND_PREVIEW"] else {
            throw XCTSkip("UNDERGROUND_PREVIEW=<file.json> writes the preview's meshes")
        }
        let (stations, scene) = stations(try world(island: true))
        let box = try XCTUnwrap(stations.boxes.first)
        let rails = box.path[0].y
        let middle = box.path[box.path.count / 2], across = Map3DMesh.acrossDirections(box.path)[box.path.count / 2]
        let island = middle.z + across.z * (box.left + box.right) / 2
        let xs = box.path.map(\.x)
        var positions: [Float] = [], colours: [Int] = [], lit: [Bool] = [], indices: [Int] = []
        for chunk in scene.chunks {
            let mesh = chunk.mesh
            var kept: [Int: Int] = [:]
            for triangle in stride(from: 0, to: chunk.baseIndexCount, by: 3) {
                let corners = (0..<3).map { Int(mesh.indices[triangle + $0]) }
                let points = corners.map { mesh.vertices[$0] }
                guard points.allSatisfy({ $0.y <= rails + 9 && $0.y >= rails - 3 && abs($0.z - island) < 40
                    && $0.x > xs.min()! - 120 && $0.x < xs.max()! + 120 }) else { continue }
                for corner in corners {
                    if kept[corner] == nil {
                        let vertex = mesh.vertices[corner]
                        kept[corner] = lit.count
                        positions += [vertex.x, vertex.y, vertex.z]
                        colours.append(Int(vertex.color & 0xFF_FFFF))
                        lit.append(vertex.glows || vertex.layer == Map3DVertex.nightLit)
                    }
                    indices.append(kept[corner]!)
                }
            }
        }
        let json: [String: Any] = ["start": xs.min()!, "end": xs.max()!, "rails": rails, "island": island,
                                   "positions": positions, "colours": colours, "lit": lit, "indices": indices]
        try JSONSerialization.data(withJSONObject: json).write(to: URL(fileURLWithPath: out))
    }

    // MARK: Real maps

    /// Hong Kong's lines all bought (Lei Tung, on the South Island Line, is
    /// the station they lay in a tunnel; Taipei Main's are checked in
    /// ``Map3DXRayRealTests``): each underground platform in its
    /// station's box, room for its track's bore either side, one level to
    /// a box. Fukuoka's subway stations are laid at the ground or in
    /// cuttings, not in tunnels (decision 860's next step).
    func testRealUndergroundStationsAreBoxedRoundTheirPlatforms() throws {
        var report: [String] = []
        for (name, world) in try realWorlds() {
            let snapshot = world.railwaySnapshot()
            let origin = (x: Double(world.bounds.width) / 2, y: Double(world.bounds.height) / 2)
            let point = { (c: WorldCoordinate) in
                Map3DPoint(Float((Double(c.x) - origin.x) / Self.metre), Float(Double(c.z) / Self.metre), Float((Double(c.y) - origin.y) / Self.metre))
            }
            let stations = Stations(snapshot, point: point, cover: Map3DTrackCover())
            let buried = snapshot.platforms.filter { $0.structure == .tunnel && $0.points.count > 1 }
            XCTAssertEqual(stations.platforms.count, buried.count, name)
            XCTAssertFalse(stations.boxes.isEmpty, name)
            var islands = 0
            for box in stations.boxes {
                for index in box.platforms {
                    let platform = stations.platforms[index]
                    XCTAssertEqual(platform.station, box.station, name)
                    let middle = try XCTUnwrap(Stations.locate(platform.line[platform.line.count / 2], along: box.path), name)
                    // Its track's bore room and its platform inside the box.
                    XCTAssertGreaterThanOrEqual(middle.across - box.left, Map3DScene.Builder.boreHalfWidth - 0.01, name)
                    XCTAssertGreaterThanOrEqual(box.right - middle.across, Map3DScene.Builder.boreHalfWidth - 0.01, name)
                    if platform.island { islands += 1 }
                }
                // One level to a box.
                let levels = box.platforms.map { stations.platforms[$0].line[stations.platforms[$0].line.count / 2].y }
                XCTAssertLessThanOrEqual((levels.max() ?? 0) - (levels.min() ?? 0), Map3DXRay.sameLevel, name)
            }
            report.append("\(name): \(buried.count) underground platforms, \(stations.boxes.count) boxes, \(islands / 2) islands")
        }
        print("UNDERGROUND STATIONS\n" + report.joined(separator: "\n"))
    }

    private func realWorlds() throws -> [(String, GameWorld)] {
        var worlds: [(String, GameWorld)] = []
        let hongKong = try HongKongMapTests.hongKong()
        _ = try SharedStationLayoutTests.buy(hongKong.buyableRealLines.map(\.id).sorted(), on: hongKong)
        worlds.append(("Hong Kong", hongKong.world))
        return worlds
    }
}
