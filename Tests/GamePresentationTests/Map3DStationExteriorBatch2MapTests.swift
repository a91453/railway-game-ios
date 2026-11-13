import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 665: the second batch's nine exterior studies (decision 626)
/// stood on the 3D map as the first batch's are (decision 625): where
/// OpenStreetMap has each, cut clear of the track and the platforms the
/// scene draws, standing for the kit's building of the station they are.
@MainActor
final class Map3DStationExteriorBatch2MapTests: XCTestCase {
    typealias Batch2 = Map3DStationExteriorBatch2.Station
    typealias Tests = Map3DStationExteriorsTests

    /// The real station each study's world is anchored at (the sugar
    /// railways' nearest TRA station), and whether the demo's real lines
    /// are laid round it. The real lines' track is drawn either way, so
    /// only Keelung's, for a station of the game the study stands for
    /// (laying them is most of the time these tests take).
    static let anchoredAt: [Batch2: (system: String, name: String, lays: Bool)] = [
        .keelung: ("tra_sched", "基隆", true), .chiayi: ("tra_sched", "嘉義", false), .tainan: ("tra_sched", "臺南", false),
        .beimen: ("afr_sched", "北門", false), .fenqihu: ("afr_sched", "奮起湖", false), .alishan: ("afr_sched", "阿里山", false),
        .wushulin: ("tra_sched", "後壁", false), .xihu: ("tra_sched", "員林", false), .qiaotou: ("tra_sched", "橋頭", false),
    ]

    static func world(round station: Batch2) async throws -> GameSession {
        let at = try XCTUnwrap(anchoredAt[station])
        let (session, view) = try DemoRealLinesTrackReportTests.game(at: at.name, in: at.system, half: 4_000)
        if at.lays { _ = await session.layDemoRealLines(in: view) }
        return session
    }

    struct Built {
        var builder: Map3DScene.Builder
        let frame: RealWorldFrame
        let stations: Set<Map3DScene.ChunkKey>
        let world: GameWorld
        let region: WorldRegion
    }

    /// What the scene does 900 m each way round `station`'s origin up to
    /// its stations, in its order (``Map3DStationExteriorsTests/built(round:in:heights:railways:studies:)``).
    static func built(round station: Batch2) async throws -> Built {
        if let held = cache[station] { return held }
        let session = try await world(round: station)
        let made = try built(round: station, in: session)
        cache[station] = made
        return made
    }

    static func built(round station: Batch2, in session: GameSession, studies: WorldRegion? = nil) throws -> Built {
        let world = session.world
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let origin = Map3DExteriorStudy.batch2(station).origin
        let middle = frame.worldPosition(latitude: origin.latitude, longitude: origin.longitude)
        let reach = 900 * Double(WorldCoordinate.unitsPerMetre)
        let region = WorldRegion(minX: middle.x - reach, minY: middle.y - reach, maxX: middle.x + reach, maxY: middle.y + reach)
        var builder = Map3DScene.Builder(originX: middle.x.rounded(), originY: middle.y.rounded(), region: region, world: world,
                                         heights: session.heights)
        builder.studyRegion = studies
        let snapshot = world.railwaySnapshot()
        builder.trackCover = Map3DTrackCover(snapshot, builder: &builder)
        builder.addGround(water: true)
        let cleared = builder.addTrack(snapshot)
        builder.addPlatforms(snapshot)
        let realTrains = Map3DScene.realTrains(world: world, railways: session.railways, snapshot: snapshot, builder: &builder)
        builder.realTrackLines = realTrains?.shownLanes ?? []
        builder.addViaducts()
        _ = builder.addStationExteriors(snapshot, frame: frame)
        let stations = cleared.union(builder.addStations(snapshot, frame: frame, shops: false))
        return Built(builder: builder, frame: frame, stations: stations, world: world, region: region)
    }

    static var cache: [Batch2: Built] = [:]

    // MARK: - Without the real data

    /// Keelung, Chiayi and Tainan are the kit's recipes of their own; the
    /// forest and sugar railways' stations share theirs, so stand for a
    /// station only by its platforms.
    func testTheRecipesWithAStudy() {
        XCTAssertEqual(Map3DExteriorStudy.study(for: .keelung), .batch2(.keelung))
        XCTAssertEqual(Map3DExteriorStudy.study(for: .chiayi), .batch2(.chiayi))
        XCTAssertEqual(Map3DExteriorStudy.study(for: .tainan), .batch2(.tainan))
        XCTAssertEqual(Map3DExteriorStudy.study(for: .taichung), .batch1(.taichungTRA))
        for profile in [Map3DStationKit.Profile.timber, .heritage, .halt, .regional, .elevated] {
            XCTAssertNil(Map3DExteriorStudy.study(for: profile), "\(profile)")
        }
        XCTAssertEqual(Map3DExteriorStudy.allCases.count, 20)
        XCTAssertEqual(Set(Map3DExteriorStudy.allCases.map(\.rawValue)).count, 20)
    }

    /// Each study's outlines, on the ground round its origin, and the
    /// scene's mesh its own north to south, each triangle turned with it,
    /// its windows lit warm after dark and nothing left glowing its pale
    /// colour.
    func testTheSceneMeshAndOutlines() {
        for station in Batch2.allCases {
            let study = Map3DExteriorStudy.batch2(station)
            XCTAssertFalse(study.outlines.isEmpty, "\(station)")
            XCTAssertTrue(study.outlines.allSatisfy { $0.count >= 3 }, "\(station)")
            for detail in [Map3DExteriorStudy.LevelOfDetail.near, .far] {
                let own = study.mesh(detail: detail), scene = study.sceneMesh(detail: detail)
                XCTAssertEqual(own.triangleCount, scene.triangleCount)
                XCTAssertGreaterThan(own.triangleCount, 0)
                for (a, b) in zip(own.vertices, scene.vertices) {
                    XCTAssertEqual(a.x, b.x); XCTAssertEqual(a.y, b.y); XCTAssertEqual(a.z, -b.z)
                }
                XCTAssertFalse(scene.vertices.contains { $0.layer == Map3DVertex.glowing }, "\(station) \(detail)")
                if detail == .near {
                    XCTAssertTrue(scene.vertices.contains { $0.layer == Map3DVertex.floodlit }, "\(station) lit at night")
                }
                // The turn and the normal agree as they did in its own axes.
                func facing(_ mesh: Map3DMesh, _ start: Int) -> Float {
                    let c = (0..<3).map { mesh.vertices[Int(mesh.indices[start + $0])] }
                    let face = (c[1].position - c[0].position).cross(c[2].position - c[0].position)
                    return face.dot(Map3DPoint(c[0].nx, c[0].ny, c[0].nz))
                }
                for start in stride(from: 0, to: scene.indices.count, by: 3) {
                    let (o, n) = (facing(own, start), facing(scene, start))
                    if abs(o) > 1e-4 { XCTAssertEqual(o > 0, n > 0, "\(station) triangle \(start / 3)") }
                }
            }
        }
    }

    // MARK: - On the real map

    /// Each study stands once, at OpenStreetMap's place, at least half of
    /// it clear, within the budget of one study (decision 625), and no
    /// part of it in a train's or a platform's room.
    func testEachStandsClearOfTheTrack() async throws {
        for station in Batch2.allCases {
            let built = try await Self.built(round: station)
            let study = Map3DExteriorStudy.batch2(station)
            let stood = built.builder.stationExteriors.filter { $0.station == study }
            XCTAssertEqual(stood.count, 1, "\(station) stands once")
            guard let exterior = stood.first else { continue }
            let place = built.frame.worldPosition(latitude: study.origin.latitude, longitude: study.origin.longitude)
            let probe = built.builder
            let expected = probe.point(x: place.x, y: place.y, height: 0)
            XCTAssertEqual(exterior.origin.x, expected.x, accuracy: 0.01)
            XCTAssertEqual(exterior.origin.z, expected.z, accuracy: 0.01)
            XCTAssertGreaterThanOrEqual(exterior.kept.near, Map3DScene.Builder.exteriorLeast, "\(station)")
            XCTAssertLessThanOrEqual(exterior.near.triangleCount, 8_000, "\(station)")
            XCTAssertLessThanOrEqual(exterior.far.triangleCount, 3_000, "\(station)")
            try Self.assertClear(exterior, in: built, station: station)
        }
    }

    /// No corner or middle of any triangle within the tests' gauge of a
    /// track drawn (the player's and the real lines') or over a platform.
    static func assertClear(_ exterior: Map3DStationExterior, in built: Built, station: Batch2) throws {
        let builder = built.builder
        let snapshot = built.world.railwaySnapshot()
        var lines: [[Map3DPoint]] = builder.realTrackLines
        for alignment in snapshot.edges {
            for span in alignment.edge.sectionSpans where span.end > span.start && span.kind != .tunnel {
                lines.append(builder.sample(alignment.geometry, from: span.start, to: span.end).map { builder.point($0) + Map3DScene.Builder.lifted })
            }
        }
        // Only the stretches that reach the study.
        let all = (exterior.near.vertices + exterior.far.vertices).map(\.position)
        let low = Map3DPoint(all.map(\.x).min()! - 10, 0, all.map(\.z).min()! - 10)
        let high = Map3DPoint(all.map(\.x).max()! + 10, 0, all.map(\.z).max()! + 10)
        let stretches = lines.flatMap { line in zip(line, line.dropFirst()).filter { a, b in
            max(a.x, b.x) > low.x && min(a.x, b.x) < high.x && max(a.z, b.z) > low.z && min(a.z, b.z) < high.z
        } }
        for mesh in [exterior.near, exterior.far] {
            for start in stride(from: 0, to: mesh.indices.count, by: 3) {
                let corners = (0..<3).map { mesh.vertices[Int(mesh.indices[start + $0])].position }
                for p in corners + [(corners[0] + corners[1] + corners[2]) * (1.0 / 3)] {
                    do {
                        for (a, b) in stretches {
                            let ab = Map3DPoint(b.x - a.x, 0, b.z - a.z), ap = Map3DPoint(p.x - a.x, 0, p.z - a.z)
                            let share = min(max(ab.dot(ap) / max(ab.dot(ab), 1e-6), 0), 1)
                            guard (ap - ab * share).length < Tests.gaugeHalf else { continue }
                            let rails = a.y + (b.y - a.y) * share
                            XCTAssertFalse(p.y > rails - 0.2 && p.y < rails + Tests.gaugeAbove,
                                           "\(station): \(p) in the room of the track at \(a)")
                        }
                    }
                }
            }
        }
    }

    /// Keelung's study stands for the demo's Keelung station (the kit's
    /// own recipe): with the study, the kit builds no building on it;
    /// with the study drawn nowhere (``Map3DScene/Builder/studyRegion``,
    /// review L14-7), the station draws its own again.
    func testItStandsForTheStation() async throws {
        let session = try await Self.world(round: .keelung)
        let plain = try Self.built(round: .keelung, in: session, studies: nil)
        let exterior = try XCTUnwrap(plain.builder.stationExteriors.first { $0.station == .batch2(.keelung) })
        let studied = exterior.outlines.map(Map3DStationExterior.rectangle(round:))
        for footprint in plain.builder.houseFootprints where !studied.contains(footprint) {
            let middle = footprint.reduce(Map3DPoint(0, 0, 0)) { $0 + $1 } * (1 / Float(footprint.count))
            for corner in footprint + [middle] {
                XCTAssertFalse(exterior.covers(corner, margin: 0), "the kit's building on Keelung's study")
            }
        }
        let east = WorldRegion(minX: plain.region.maxX, minY: plain.region.minY, maxX: plain.region.maxX + 1, maxY: plain.region.maxY)
        let without = try Self.built(round: .keelung, in: session, studies: east)
        // Decision 722: the kit's building is in the look already, apart
        // from the chunk's near mesh.
        func triangles(_ builder: Map3DScene.Builder) -> Int { builder.nearMeshes.values.reduce(0) { $0 + $1.triangleCount } + builder.houseTriangleCount }
        XCTAssertGreaterThan(triangles(without.builder), triangles(plain.builder), "Keelung's own building")
        XCTAssertGreaterThan(without.builder.houseFootprints.count, plain.builder.houseFootprints.count - exterior.outlines.count)
    }

    /// `STATION_EXTERIOR_REPORT=1`: what stands of each, for decision 665.
    func testReportWhatStands() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["STATION_EXTERIOR_REPORT"] == "1")
        for station in Batch2.allCases {
            let built = try await Self.built(round: station)
            let study = Map3DExteriorStudy.batch2(station)
            let full = (study.mesh(detail: .near).triangleCount, study.mesh(detail: .far).triangleCount)
            if let exterior = built.builder.stationExteriors.first(where: { $0.station == study }) {
                print("STATION-EXTERIOR \(station.rawValue) kept \(exterior.kept.near)/\(exterior.kept.far) tris \(exterior.near.triangleCount)/\(exterior.far.triangleCount) whole \(full.0)/\(full.1) lines \(built.builder.realTrackLines.count) platforms \(built.world.network.platforms.count)")
            } else {
                print("STATION-EXTERIOR \(station.rawValue) does not stand; whole \(full.0)/\(full.1)")
            }
        }
    }
}
