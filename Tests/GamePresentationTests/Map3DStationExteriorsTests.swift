import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 625: the eleven exterior studies of #1904 stood on the 3D map
/// where OpenStreetMap has the real stations, as the landmarks are
/// (decision 370), in the demo's real lines laid round each (decision
/// 351) or the high-speed demo's line, cut clear of the track and the
/// platforms; the kit's building of the station they stand for, and the
/// real buildings under them, left out.
@MainActor
final class Map3DStationExteriorsTests: XCTestCase {
    typealias Study = Map3DStationExteriorBatch1.Station

    /// The real station each study's demo is laid round: its system and
    /// name in the bundled data. The high-speed ones are on the
    /// high-speed demo's map.
    static let laidAt: [Study: (system: String, name: String)] = [
        .taichungTRA: ("tra_sched", "臺中"), .hsinchuTRA: ("tra_sched", "新竹"), .hualienTRA: ("tra_sched", "花蓮"),
        .taitungTRA: ("tra_sched", "臺東"), .banqiaoTRA: ("tra_sched", "板橋"), .nangangTRA: ("tra_sched", "南港"),
        .taoyuanHSR: ("thsr_sched", "桃園"), .hsinchuHSR: ("thsr_sched", "新竹"), .taichungHSR: ("thsr_sched", "台中"),
        .tainanHSR: ("thsr_sched", "台南"), .zuoyingHSR: ("thsr_sched", "左營"),
    ]

    /// Building gauge the tests hold the studies to, smaller than the room
    /// cut (``Map3DTrainRoom``, 3.2 m and 6.5 m) by what the cut's 1.5 m
    /// sampling may leave: no part of a study within 2.2 m of a track's
    /// middle from 0.2 m under its rails to 5.5 m over them (a car 3.4 m
    /// wide, its pantograph and wire); none over a platform to 2.4 m
    /// (people on it).
    static let gaugeHalf: Float = 2.2, gaugeAbove: Float = 5.5, platformAbove: Float = 2.4

    /// The world each study is tried in: the demo's real lines laid 4 km
    /// each way round the TRA ones, the high-speed demo for the others.
    static func world(round study: Study) async throws -> (world: GameWorld, heights: HeightGrid?, railways: RealRailways?) {
        let at = try XCTUnwrap(laidAt[study])
        if at.system == "thsr_sched" {
            return (try HighSpeedDemoTests.opened.get(), HighSpeedDemoTests.heights, try HighSpeedDemoTests.railways())
        }
        let (session, view) = try DemoRealLinesTrackReportTests.game(at: at.name, in: at.system, half: 4_000)
        _ = await session.layDemoRealLines(in: view)
        return (session.world, session.heights, session.railways)
    }

    /// The scene's region 900 m each way round `study`'s origin.
    static func region(round study: Study, frame: RealWorldFrame) -> (region: WorldRegion, x: Double, y: Double) {
        let origin = Map3DStationExteriorBatch1.origin(of: study)
        let middle = frame.worldPosition(latitude: origin.latitude, longitude: origin.longitude)
        let reach = 900 * Double(WorldCoordinate.unitsPerMetre)
        return (WorldRegion(minX: middle.x - reach, minY: middle.y - reach, maxX: middle.x + reach, maxY: middle.y + reach),
                middle.x.rounded(), middle.y.rounded())
    }

    /// The 3D scene of `world` 900 m each way round `study`'s origin.
    static func scene(round study: Study, in world: GameWorld, heights: HeightGrid?, railways: RealRailways?) throws -> Map3DScene {
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let (region, x, y) = region(round: study, frame: frame)
        return Map3DScene(world: world, snapshot: world.railwaySnapshot(), skyline: nil, frame: (region, x, y),
                          baseMap: nil, cityTiles: [], heights: heights, lineBands: nil, railways: railways, temples: nil)
    }

    /// What the scene does round a study up to its stations, in its
    /// order: the track, the platforms, the real lines and the viaducts,
    /// the studies, the kit's stations.
    struct Built {
        var builder: Map3DScene.Builder
        let frame: RealWorldFrame
        let exteriors: [Study: Set<Map3DScene.ChunkKey>]
        let stations: Set<Map3DScene.ChunkKey>
    }

    static func built(round study: Study, in world: GameWorld, heights: HeightGrid?, railways: RealRailways?) throws -> Built {
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let (region, x, y) = region(round: study, frame: frame)
        var builder = Map3DScene.Builder(originX: x, originY: y, region: region, world: world, heights: heights)
        let snapshot = world.railwaySnapshot()
        builder.trackCover = Map3DTrackCover(snapshot, builder: &builder)
        builder.addGround(water: true)
        let cleared = builder.addTrack(snapshot)
        builder.addPlatforms(snapshot)
        let realTrains = Map3DScene.realTrains(world: world, railways: railways, snapshot: snapshot, builder: &builder)
        builder.realTrackLines = realTrains?.shownLanes ?? []
        builder.addViaducts()
        let exteriors = builder.addStationExteriors(snapshot, frame: frame)
        let stations = cleared.union(builder.addStations(snapshot, frame: frame, shops: false))
        return Built(builder: builder, frame: frame, exteriors: exteriors, stations: stations)
    }

    /// Each study's world and what was built round it, once a run.
    static var cache: [Study: (world: GameWorld, built: Built)] = [:]

    static func built(round study: Study) async throws -> (world: GameWorld, built: Built) {
        if let held = cache[study] { return held }
        let (world, heights, railways) = try await world(round: study)
        let made = (world, try built(round: study, in: world, heights: heights, railways: railways))
        cache[study] = made
        return made
    }

    // MARK: - Without the real data

    /// Each study is the station kit's recipe of the same station, and no
    /// other recipe has one.
    func testEachRecipeHasItsStudy() {
        let expected: [Map3DStationKit.Profile: Study] = [
            .taichung: .taichungTRA, .hsinchu: .hsinchuTRA, .hualien: .hualienTRA, .taitung: .taitungTRA,
            .banqiao: .banqiaoTRA, .nangang: .nangangTRA, .hsrTaoyuan: .taoyuanHSR, .hsrHsinchu: .hsinchuHSR,
            .hsrTaichung: .taichungHSR, .hsrTainan: .tainanHSR, .zuoying: .zuoyingHSR,
        ]
        for profile in Map3DStationKit.Profile.allCases {
            XCTAssertEqual(Map3DStationExteriorBatch1.study(for: profile), expected[profile], "\(profile)")
        }
        XCTAssertEqual(Set(expected.values), Set(Study.allCases))
    }

    /// The study's model (x east, z north) turned into the scene's (z
    /// south): each outline's corners where its slab is, its faces still
    /// turned out.
    func testTheSceneMeshIsTheStudyNorthToSouth() {
        for study in Study.allCases {
            for detail in [Map3DStationExteriorBatch1.LevelOfDetail.near, .far] {
                let mesh = Map3DStationExteriorBatch1.sceneMesh(for: study, detail: detail)
                XCTAssertEqual(mesh.triangleCount, Map3DStationExteriorBatch1.mesh(for: study, detail: detail).triangleCount)
                // Each outline corner (east e, north n) at (e, z = −n).
                let corners = Map3DStationExteriorBatch1.outlines(of: study).flatMap { $0 }
                let found = corners.filter { corner in
                    mesh.vertices.contains { abs($0.x - corner.0) < 0.05 && abs($0.z + corner.1) < 0.05 }
                }
                XCTAssertGreaterThanOrEqual(Float(found.count), Float(corners.count) * 0.9, "\(study) \(detail)")
                // The winding agrees with the normals.
                var agree = 0
                for t in 0..<mesh.triangleCount {
                    let v = (0..<3).map { mesh.vertices[Int(mesh.indices[t * 3 + $0])] }
                    let face = (v[1].position - v[0].position).cross(v[2].position - v[0].position)
                    if face.dot(Map3DPoint(v[0].nx, v[0].ny, v[0].nz)) >= 0 { agree += 1 }
                }
                XCTAssertGreaterThan(Float(agree), Float(mesh.triangleCount) * 0.95, "\(study) \(detail)")
            }
        }
    }

    /// A building cut through by a track: the walls stop either side of
    /// it, a roof high over it stays.
    func testTheCutLeavesTheTrackRoomAndWhatStands() {
        // A 20 m box 4 m high on the ground, a slab roof 10 m up on four
        // posts, a track along its middle.
        var kit = StationKitBuilder()
        kit.box(0, 0, 0, 20, 20, 4, Map3DPalette.concrete)
        kit.box(0, 10, 0, 20, 20, 0.4, Map3DPalette.concrete)
        for (x, z): (Float, Float) in [(-9, -9), (9, -9), (-9, 9), (9, 9)] { kit.box(x, 0, z, 0.5, 0.5, 10, Map3DPalette.concrete) }
        var room = Map3DTrainRoom()
        room.add(line: [Map3DPoint(-40, 0.3, 0), Map3DPoint(40, 0.3, 0)], half: Map3DTrainRoom.trackHalf, above: Map3DTrainRoom.trackAbove, ground: 0)
        let cut = Map3DStationExterior.carved(kit.mesh, clearOf: room, ground: 0)
        XCTAssertGreaterThan(cut.kept, 0.5)
        XCTAssertLessThan(cut.kept, 1)
        let left = cut.mesh.vertices.map(\.position)
        XCTAssertFalse(left.contains { abs($0.z) < Self.gaugeHalf && $0.y > 0.1 && $0.y < 0.3 + Self.gaugeAbove }, "nothing in the room")
        let over = (0..<cut.mesh.triangleCount).contains { t in
            let v = (0..<3).map { cut.mesh.vertices[Int(cut.mesh.indices[t * 3 + $0])].position }
            return v.allSatisfy { $0.y > 10 } && v.contains { $0.z < 0 } && v.contains { $0.z > 0 }
        }
        XCTAssertTrue(over, "the roof over the track")
        XCTAssertTrue(left.contains { $0.y > 3.9 && $0.y < 4.1 && abs($0.z) > 4 }, "the box's top either side")
        // Nothing in the way: all of it.
        let clear = Map3DStationExterior.carved(kit.mesh, clearOf: Map3DTrainRoom(), ground: 0)
        XCTAssertEqual(clear.kept, 1)
        XCTAssertEqual(clear.mesh.triangleCount, kit.mesh.triangleCount)
    }

    /// On a map of nowhere, and on a real map far from them, none stands.
    func testNoneOffTheRealStations() throws {
        XCTAssertTrue(Map3DScene(world: GameWorld.newGame()).stationExteriors.isEmpty)
        // Kenting, far from all of them.
        let world = GameWorld.newGame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: 21.95, longitudeDegrees: 120.78)))
        XCTAssertTrue(Map3DScene(world: world).stationExteriors.isEmpty)
    }

    // MARK: - With the real data

    /// Each study stands once, where OpenStreetMap has it, with most of it
    /// left and within the triangles a landmark may have, on its ground.
    func testEachStandsWhereOpenStreetMapHasIt() async throws {
        for study in Study.allCases {
            let (_, built) = try await Self.built(round: study)
            let stood = built.builder.stationExteriors.filter { $0.station == study }
            XCTAssertEqual(stood.count, 1, "\(study) stands once")
            guard let exterior = stood.first else { continue }
            XCTAssertNotNil(built.exteriors[study])
            // Its origin where the frame puts OSM's, to the centimetre;
            // the study's own corners are OSM's metres round it.
            let origin = Map3DStationExteriorBatch1.origin(of: study)
            let place = built.frame.worldPosition(latitude: origin.latitude, longitude: origin.longitude)
            let expected = built.builder.point(x: place.x, y: place.y, height: 0)
            XCTAssertEqual(exterior.origin.x, expected.x, accuracy: 0.01, "\(study)")
            XCTAssertEqual(exterior.origin.z, expected.z, accuracy: 0.01, "\(study)")
            XCTAssertGreaterThanOrEqual(exterior.kept.near, Map3DScene.Builder.exteriorLeast, "\(study)")
            XCTAssertLessThanOrEqual(exterior.near.triangleCount, 12_000, "\(study) near")
            XCTAssertLessThanOrEqual(exterior.far.triangleCount, 3_000, "\(study) far")
            let lowest = exterior.near.vertices.map(\.y).min() ?? 0
            XCTAssertGreaterThanOrEqual(lowest, exterior.origin.y - 0.01, "\(study)")
        }
    }

    /// No part of a study is in the building gauge (``gaugeHalf``) of any
    /// track drawn, the player's or a real line's, nor over any platform;
    /// under a viaduct, nothing between the ground and its rails.
    func testClearOfTheTrackAndThePlatforms() async throws {
        for study in Study.allCases {
            let (_, built) = try await Self.built(round: study)
            guard let exterior = built.builder.stationExteriors.first(where: { $0.station == study }) else { continue }
            XCTAssertEqual(Self.inTheGauge(exterior.near, built.builder, ground: exterior.origin.y), 0, "\(study) near")
            XCTAssertEqual(Self.inTheGauge(exterior.far, built.builder, ground: exterior.origin.y), 0, "\(study) far")
        }
    }

    /// How many corners and middles of `mesh`'s triangles are in a track's
    /// gauge or over a platform of `builder`'s.
    static func inTheGauge(_ mesh: Map3DMesh, _ builder: Map3DScene.Builder, ground: Float) -> Int {
        var points: [Map3DPoint] = []
        for t in 0..<mesh.triangleCount {
            let v = (0..<3).map { mesh.vertices[Int(mesh.indices[t * 3 + $0])].position }
            points += v
            points.append((v[0] + v[1] + v[2]) * (1 / 3))
        }
        guard !points.isEmpty else { return 0 }
        let minX = points.map(\.x).min()! - 10, maxX = points.map(\.x).max()! + 10
        let minZ = points.map(\.z).min()! - 10, maxZ = points.map(\.z).max()! + 10
        func near(_ a: Map3DPoint, _ b: Map3DPoint) -> Bool {
            max(a.x, b.x) > minX && min(a.x, b.x) < maxX && max(a.z, b.z) > minZ && min(a.z, b.z) < maxZ
        }
        var hits = 0
        let lines = builder.trackLines.filter { $0.kind != .tunnel }.map(\.points) + builder.realTrackLines
        for line in lines {
            for (a, b) in zip(line, line.dropFirst()) where near(a, b) {
                let ab = Map3DPoint(b.x - a.x, 0, b.z - a.z)
                for p in points {
                    let ap = Map3DPoint(p.x - a.x, 0, p.z - a.z)
                    let share = min(max(ab.dot(ap) / max(ab.dot(ab), 1e-6), 0), 1)
                    guard (ap - ab * share).length < gaugeHalf else { continue }
                    let rails = a.y + (b.y - a.y) * share
                    let from = rails - ground > Map3DTrainRoom.raised ? ground + 1.2 : rails - 0.2
                    if p.y > from && p.y < rails + gaugeAbove { hits += 1 }
                }
            }
        }
        for platform in builder.laidPlatforms where platform.structure != .tunnel {
            for (a, b) in zip(platform.line, platform.line.dropFirst()) where near(a, b) {
                guard let along = Map3DPoint(b.x - a.x, 0, b.z - a.z).normalized else { continue }
                // Its middle `offset` to the line's right, as the scene lays it.
                let right = along.cross(.up)
                let (pa, pb) = (a + right * platform.offset, b + right * platform.offset)
                let ab = Map3DPoint(pb.x - pa.x, 0, pb.z - pa.z)
                for p in points {
                    let ap = Map3DPoint(p.x - pa.x, 0, p.z - pa.z)
                    let share = min(max(ab.dot(ap) / max(ab.dot(ab), 1e-6), 0), 1)
                    guard (ap - ab * share).length < platform.width / 2 else { continue }
                    let top = pa.y + (pb.y - pa.y) * share + Map3DScene.Builder.platformHeight
                    if p.y > top + 0.1 && p.y < top + platformAbove { hits += 1 }
                }
            }
        }
        return hits
    }

    /// Where a study stands, it is the one building: the station kit
    /// builds none of its own on it, and a real building's footprint
    /// there is not drawn.
    func testTheOneBuildingThere() async throws {
        for study in Study.allCases {
            var (_, built) = try await Self.built(round: study)
            guard let exterior = built.builder.stationExteriors.first(where: { $0.station == study }) else { continue }
            let studied = exterior.outlines.map(Map3DStationExterior.rectangle(round:))
            for footprint in built.builder.houseFootprints where !studied.contains(footprint) {
                let middle = footprint.reduce(Map3DPoint(0, 0, 0)) { $0 + $1 } * (1 / Float(footprint.count))
                for corner in footprint + [middle] {
                    XCTAssertFalse(exterior.covers(corner, margin: 0), "\(study): the kit's building on it")
                }
            }
            // A 10 m real building at each outline's middle.
            let m = Map3DScene.Builder.metre
            let buildings = exterior.outlines.map { outline -> Map3DFootprints.Building in
                let middle = outline.reduce(Map3DPoint(0, 0, 0)) { $0 + $1 } * (1 / Float(outline.count))
                let x = built.builder.originX + Double(middle.x) * m, y = built.builder.originY + Double(middle.z) * m
                return Map3DFootprints.Building(storeys: 3, storeysFrom: .guess, use: 431,
                                                rings: [[(x, y), (x, y + 10 * m), (x + 10 * m, y + 10 * m), (x + 10 * m, y)]])
            }
            let cells = built.exteriors[study] ?? []
            built.builder.target = .near
            let standing = built.builder.addFootprints(Map3DFootprints(buildings: buildings), clearOf: built.stations.union(cells), takenBy: [])
            XCTAssertTrue(standing.isEmpty, "\(study): a real building drawn on it")
        }
    }

    /// An expanded station a study stands for keeps its wings, beside the
    /// study and clear of the track.
    func testAnExpandedStationKeepsItsWings() async throws {
        let (world, heights, railways) = try await Self.world(round: .banqiaoTRA)
        let plain = try Self.built(round: .banqiaoTRA, in: world, heights: heights, railways: railways)
        let study = try XCTUnwrap(plain.builder.stationExteriors.first { $0.station == .banqiaoTRA })
        let snapshot = world.railwaySnapshot()
        let within = snapshot.platforms.filter { platform in
            platform.points.contains { study.covers(plain.builder.point($0), margin: Map3DScene.Builder.exteriorCovers) }
        }
        let id = try XCTUnwrap(within.first?.platform.station)
        // Expanded as a save would have it (a day of passengers enough
        // to expand it would take minutes here).
        let name = try XCTUnwrap(world.station(id: id)?.name)
        var tree = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(world)) as? [String: Any])
        var stations = try XCTUnwrap(tree["stations"] as? [[String: Any]])
        let index = try XCTUnwrap(stations.firstIndex { $0["name"] as? String == name })
        stations[index]["expansion"] = StationExpansion.hall.rawValue
        tree["stations"] = stations
        let expanded = try JSONDecoder().decode(GameWorld.self, from: JSONSerialization.data(withJSONObject: tree))
        XCTAssertEqual(expanded.station(id: id)?.expansion, .hall)
        let grown = try Self.built(round: .banqiaoTRA, in: expanded, heights: heights, railways: railways)
        func triangles(_ builder: Map3DScene.Builder) -> Int { builder.nearMeshes.values.reduce(0) { $0 + $1.triangleCount } }
        XCTAssertGreaterThan(triangles(grown.builder), triangles(plain.builder))
        XCTAssertTrue(grown.stations.isStrictSuperset(of: plain.stations))
        // The wings alone: what they add to the plain scene's meshes.
        var alone = plain.builder
        let before = alone.nearMeshes
        let taken = alone.addExpansionWings(.hall, beside: .banqiaoTRA, frame: plain.frame, snapshot: snapshot)
        XCTAssertFalse(taken.isEmpty)
        var wings = Map3DMesh()
        for (key, mesh) in alone.nearMeshes {
            let from = (before[key]?.indices.count ?? 0)
            guard mesh.indices.count > from else { continue }
            wings.append(Map3DMesh(vertices: mesh.vertices, indices: Array(mesh.indices[from...])), at: Map3DPoint(0, 0, 0), forward: Map3DPoint(1, 0, 0))
        }
        XCTAssertGreaterThan(wings.triangleCount, 0)
        XCTAssertEqual(Self.inTheGauge(wings, plain.builder, ground: study.origin.y), 0, "the wings clear of the track")
    }

    /// For the session's own look: what stands round each, how much of it
    /// and how long it takes. `STATION_EXTERIOR_REPORT=1` only.
    func testReportWhatStands() async throws {
        guard ProcessInfo.processInfo.environment["STATION_EXTERIOR_REPORT"] == "1" else { throw XCTSkip("report") }
        for study in Study.allCases {
            let started = Date()
            let (world, heights, railways) = try await Self.world(round: study)
            let scene = try Self.scene(round: study, in: world, heights: heights, railways: railways)
            let stood = scene.stationExteriors.map {
                "\($0.station.rawValue) near \($0.kept.near) far \($0.kept.far) tris \($0.near.triangleCount)/\($0.far.triangleCount)"
            }
            let full = (Map3DStationExteriorBatch1.mesh(for: study, detail: .near).triangleCount,
                        Map3DStationExteriorBatch1.mesh(for: study, detail: .far).triangleCount)
            print("EXTERIOR \(study.rawValue): stations \(world.stations.count) stood \(stood) full \(full) in \(Int(Date().timeIntervalSince(started))) s")
        }
    }
}
