import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 370 (step 2): Taipei 101 and Taipei Main Station in the model
/// look, where they stand; decision 431's Kaohsiung Main Station and
/// decision 457's central Taipei.
final class Map3DTaipeiLandmarksTests: XCTestCase {
    /// Taipei Main Station: the middle of the map, so of the scene; 101 is
    /// 4.8 km off, outside a new game's scene.
    private let anchor = GeoAnchor(latitudeDegrees: 25.0478, longitudeDegrees: 121.5170)!

    private func builder(_ world: GameWorld) -> Map3DScene.Builder {
        let (region, originX, originY) = Map3DScene.frame(world: world, focus: nil)
        return Map3DScene.Builder(originX: originX, originY: originY, region: region, world: world, heights: nil)
    }

    private func triangles(_ meshes: [Map3DScene.ChunkKey: Map3DMesh]) -> Int {
        meshes.values.reduce(0) { $0 + $1.indices.count / 3 }
    }

    private static let wall = Map3DColor.rgb(0xF5F1E9)
    private static let canopyGrass = Map3DColor.rgb(0xCFE0C8)

    /// OSM specifications (ODbL):
    /// - Taipei 101: relation 11551064, spire way 615183623 (height = 508 m).
    /// - Taipei Main Station: way 23641610 (height = 30 m).
    /// - Kaohsiung Main Station: relation 14940189, outer canopy way 1298938821
    ///   (664.78 m east-west × 333.87 m north-south; canopy crest 23 m),
    ///   and historic Old Kaohsiung Station way 257770396 (25.30 m × 30.36 m,
    ///   building:levels = 3, Imperial Crown tower top 16.86 m).
    private static let kaohsiungCanopyLength: Float = 664.78
    private static let kaohsiungCanopyWidth: Float = 333.87
    private static let kaohsiungCanopyHeight: Float = 23.0
    private static let kaohsiungOldStationWidth: Float = 25.30
    private static let kaohsiungOldStationDepth: Float = 30.36

    /// The landmarks as OSM has their plans and heights: 101 508 m to its
    /// spire, Taipei Main Station's roof 30 m, Kaohsiung Main Station's
    /// canopy 23 m (way 1298938821) with the Imperial Crown old station
    /// (way 257770396); each within the ground it clears, lit by finite
    /// unit outward normals, drawn with the line patterns; from afar,
    /// fewer triangles.
    func testTheModels() {
        let layers: Set<Float> = [Map3DVertex.plain, Map3DVertex.curtainGlass, Map3DVertex.roofTiles, Map3DVertex.floorLines,
                                  Map3DVertex.towerGlass, Map3DVertex.floodlit, Map3DVertex.glowing]
        for landmark in Map3DTaipeiLandmark.allCases {
            let full = landmark.model(full: true), far = landmark.model(full: false)
            XCTAssertLessThan(far.indices.count, full.indices.count * 2 / 3, "\(landmark)")
            XCTAssertGreaterThanOrEqual(landmark.clearing.x, landmark.body.x, "\(landmark)")
            XCTAssertGreaterThanOrEqual(landmark.clearing.y, landmark.body.y, "\(landmark)")
            let expectedTop: Float = switch landmark {
            case .taipei101: 508
            case .taipeiMainStation: 30
            case .kaohsiungMainStation: Self.kaohsiungCanopyHeight
            case .chiangKaiShekMemorialHall: 70
            case .libertySquareGate, .sunYatSenMemorialHall: 30
            case .nationalTheater, .nationalConcertHall: 37
            case .presidentialOffice: 60
            case .ximenRedHouse: 17.5
            case .grandHotel: 87
            case .northGate: 15.2
            case .eastGate: 16.5
            case .southGate: 19
            case .smallSouthGate: 14.5
            }
            for model in [full, far] {
                let top = model.vertices.map(\.z).max() ?? 0
                XCTAssertEqual(top, expectedTop, accuracy: 0.01, "\(landmark)")
                XCTAssertEqual(model.vertices.map(\.z).min(), 0)
                for vertex in model.vertices {
                    XCTAssertTrue(vertex.x.isFinite && vertex.y.isFinite && vertex.z.isFinite)
                    XCTAssertTrue(vertex.nx.isFinite && vertex.ny.isFinite && vertex.nz.isFinite)
                    XCTAssertTrue(vertex.u.isFinite && vertex.v.isFinite)
                    XCTAssertLessThanOrEqual(abs(vertex.x), landmark.clearing.x)
                    XCTAssertLessThanOrEqual(abs(vertex.y), landmark.clearing.y)
                    XCTAssertEqual(Map3DPoint(vertex.nx, vertex.ny, vertex.nz).length, 1, accuracy: 0.001)
                    XCTAssertTrue(layers.contains(vertex.layer), "\(vertex.layer)")
                }
                XCTAssertTrue(model.indices.allSatisfy { Int($0) < model.vertices.count })
            }
            let used = Set(full.vertices.map(\.layer))
            let expectedLayers: Set<Float> = switch landmark {
            case .taipei101: [Map3DVertex.curtainGlass, Map3DVertex.towerGlass, Map3DVertex.floodlit, Map3DVertex.glowing]
            case .taipeiMainStation: [Map3DVertex.curtainGlass, Map3DVertex.roofTiles]
            case .kaohsiungMainStation: [Map3DVertex.curtainGlass, Map3DVertex.roofTiles, Map3DVertex.floorLines]
            case .chiangKaiShekMemorialHall, .libertySquareGate, .northGate, .eastGate, .southGate, .smallSouthGate:
                [Map3DVertex.plain, Map3DVertex.roofTiles]
            case .nationalTheater, .nationalConcertHall, .sunYatSenMemorialHall, .grandHotel:
                [Map3DVertex.roofTiles, Map3DVertex.floorLines]
            case .presidentialOffice: [Map3DVertex.floorLines, Map3DVertex.floodlit]
            case .ximenRedHouse: [Map3DVertex.floorLines, Map3DVertex.roofTiles]
            }
            XCTAssertTrue(used.isSuperset(of: expectedLayers), "\(landmark)")
        }
        // Pin Taipei 101 and Taipei Main Station triangle counts so adding
        // new landmarks never alters them; check Kaohsiung's budget.
        XCTAssertEqual(Map3DTaipeiLandmark.taipei101.model(full: true).indices.count / 3, 4_732)
        XCTAssertEqual(Map3DTaipeiLandmark.taipei101.model(full: false).indices.count / 3, 2_580)
        XCTAssertEqual(Map3DTaipeiLandmark.taipeiMainStation.model(full: true).indices.count / 3, 5_458)
        XCTAssertEqual(Map3DTaipeiLandmark.taipeiMainStation.model(full: false).indices.count / 3, 2_070)
        let kaohsiungFull = Map3DTaipeiLandmark.kaohsiungMainStation.model(full: true)
        let kaohsiungFar = Map3DTaipeiLandmark.kaohsiungMainStation.model(full: false)
        XCTAssertLessThanOrEqual(kaohsiungFull.indices.count / 3, 6_000)
        XCTAssertLessThanOrEqual(kaohsiungFar.indices.count / 3, 2_500)
        XCTAssertLessThan(kaohsiungFar.indices.count, kaohsiungFull.indices.count)
    }

    /// Decision 457: the Chinese roof is a part of its own: any plan, any
    /// number of eaves, only the caller's colours, its top where asked.
    func testTheChineseRoofPart() {
        let colours = ChineseRoofColours(tile: 1, ridge: 2, underside: 3, gable: nil, wall: 4)
        for kind in [LandmarkMesh.RoofKind.hipped, .hipGable] {
            for tiers in 1...3 {
                for full in [true, false] {
                    var mesh = LandmarkMesh(full: full)
                    mesh.chineseRoof(9, 6, eaves: 4, over: 1.5, rise: 3.5, sweep: 0.8, kind: kind, tiers: tiers, tierRise: 2,
                                     tierInset: 1.2, colours: colours)
                    let zs = mesh.vertices.map(\.z)
                    XCTAssertEqual(zs.max() ?? 0, 4 + Float(tiers - 1) * 2 + 3.5, accuracy: 0.001, "\(kind) \(tiers)")
                    XCTAssertGreaterThanOrEqual(zs.min() ?? 0, 4 - 0.5 - 0.001)
                    XCTAssertTrue(mesh.vertices.allSatisfy { abs($0.x) <= 9 + 1.5 + 0.4 && abs($0.y) <= 6 + 1.5 + 0.4 })
                    XCTAssertTrue(Set(mesh.vertices.map(\.color)).isSubset(of: [1, 2, 3, 4]))
                    XCTAssertEqual(mesh.vertices.contains { $0.color == 4 }, tiers > 1)
                    for v in mesh.vertices {
                        XCTAssertEqual(Map3DPoint(v.nx, v.ny, v.nz).length, 1, accuracy: 0.001)
                    }
                }
            }
        }
    }

    /// Decision 457: central Taipei's landmarks stand on OpenStreetMap's
    /// plans (the minimum box of each way, ODbL), within 2 m at the
    /// ground; each within the landmark budget.
    func testCentralTaipeiOnOSMsPlans() {
        let plans: [Map3DTaipeiLandmark: (x: Float, y: Float)] = [
            .chiangKaiShekMemorialHall: (124.4, 147.4), // way 1052759757
            .libertySquareGate: (74.7, 17.0), // way 1052759782
            .nationalTheater: (107.9, 103.3), // way 1052759776
            .nationalConcertHall: (102.9, 103.3), // way 1052759775
            .presidentialOffice: (131.9, 92.9), // relation 206817, way 39239021
            .ximenRedHouse: (91.7, 47.8), // way 222080307
            .sunYatSenMemorialHall: (108.7, 112.5), // way 189788192
            .grandHotel: (109.8, 74.2), // way 25202548
            .northGate: (15.1, 11.4), // way 238316480
            .eastGate: (17.7, 13.5), // way 209580573
            .southGate: (33.8, 19.6), // way 245993047
            .smallSouthGate: (13.5, 12.5), // way 246651384
        ]
        for (landmark, plan) in plans {
            for model in [landmark.model(full: true), landmark.model(full: false)] {
                let ground = model.vertices.filter { $0.z < 0.01 }
                let xs = ground.map(\.x), ys = ground.map(\.y)
                XCTAssertEqual((xs.max() ?? 0) - (xs.min() ?? 0), plan.x, accuracy: 2, "\(landmark)")
                XCTAssertEqual((ys.max() ?? 0) - (ys.min() ?? 0), plan.y, accuracy: 2, "\(landmark)")
                XCTAssertEqual(((xs.max() ?? 0) + (xs.min() ?? 0)) / 2, 0, accuracy: 2, "\(landmark)")
                XCTAssertEqual(((ys.max() ?? 0) + (ys.min() ?? 0)) / 2, 0, accuracy: 2, "\(landmark)")
            }
            XCTAssertLessThanOrEqual(landmark.model(full: true).indices.count / 3, 6_000, "\(landmark)")
            XCTAssertLessThanOrEqual(landmark.model(full: false).indices.count / 3, 2_500, "\(landmark)")
        }
        XCTAssertEqual(Set(plans.keys).count, Map3DTaipeiLandmark.allCases.count - 3)
        // None in Taipei Main Station's wall colour, which the tests below
        // count the station by.
        for landmark in plans.keys {
            XCTAssertFalse(landmark.model(full: true).vertices.contains { $0.color == Self.wall }, "\(landmark)")
        }
    }

    /// Decision 431: Kaohsiung Main Station's canopy (OSM relation 14940189,
    /// way 1298938821) and Imperial Crown old station (OSM way 257770396)
    /// match OpenStreetMap's dimensions within 2 m, with outward normals,
    /// and stand clear of surface track while allowing underground track.
    func testKaohsiungMainStation() throws {
        let station = Map3DTaipeiLandmark.kaohsiungMainStation
        for model in [station.model(full: true), station.model(full: false)] {
            let xs = model.vertices.map(\.x), ys = model.vertices.map(\.y), zs = model.vertices.map(\.z)
            let length = (xs.max() ?? 0) - (xs.min() ?? 0)
            let width = (ys.max() ?? 0) - (ys.min() ?? 0)
            let height = (zs.max() ?? 0) - (zs.min() ?? 0)
            XCTAssertEqual(length, Self.kaohsiungCanopyLength, accuracy: 2.0)
            XCTAssertEqual(width, Self.kaohsiungCanopyWidth, accuracy: 2.0)
            XCTAssertEqual(height, Self.kaohsiungCanopyHeight, accuracy: 2.0)
            // Old station (OSM way 257770396) on the south plaza.
            let oldStation = model.vertices.filter { $0.y < -109 && abs($0.x) < 20 }
            let oldXs = oldStation.map(\.x), oldYs = oldStation.map(\.y)
            XCTAssertEqual((oldXs.max() ?? 0) - (oldXs.min() ?? 0), Self.kaohsiungOldStationWidth, accuracy: 2.0)
            XCTAssertEqual((oldYs.max() ?? 0) - (oldYs.min() ?? 0), Self.kaohsiungOldStationDepth, accuracy: 2.0)
            // Canopy grass faces upward; canopy soffit faces downward.
            let grass = model.vertices.filter { $0.color == Self.canopyGrass }
            XCTAssertFalse(grass.isEmpty)
            XCTAssertTrue(grass.allSatisfy { $0.nz > 0 })
        }
        let kaohsiungAnchor = GeoAnchor(latitudeDegrees: station.latitude, longitudeDegrees: station.longitude)!
        let world = GameWorld.newGame(anchor: kaohsiungAnchor)
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        var builder = builder(world)
        let built = builder.addTaipeiLandmarks(frame: frame)
        XCTAssertEqual(Set(built.keys), [station])
        XCTAssertEqual(triangles(builder.nearMeshes), station.model(full: true).indices.count / 3)
        XCTAssertEqual(triangles(builder.farMeshes), station.model(full: false).indices.count / 3)
        XCTAssertTrue(builder.keptColours.contains(Self.canopyGrass))
        let middle = builder.point(x: frame.middleX, y: frame.middleY, height: 0)
        let line = stride(from: Float(-300), through: 300, by: 2).map { middle + Map3DPoint($0, 0, 20) }
        var blocked = self.builder(world)
        blocked.trackLines = [(line, .surface)]
        XCTAssertTrue(blocked.addTaipeiLandmarks(frame: frame).isEmpty)
        var tunnel = self.builder(world)
        tunnel.trackLines = [(line, .tunnel)]
        XCTAssertEqual(Set(tunnel.addTaipeiLandmarks(frame: frame).keys), [station])
    }

    /// Stood where it is, the station is in full close by and simpler from
    /// afar, in its own colours, and clears the ground under it.
    func testWhereItStands() throws {
        let world = GameWorld.newGame(anchor: anchor)
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        var builder = builder(world)
        let built = builder.addTaipeiLandmarks(frame: frame)
        let station = Map3DTaipeiLandmark.taipeiMainStation
        // With it, decision 457's central Taipei within the scene; 101,
        // the Sun Yat-sen Memorial Hall and the Grand Hotel are not.
        XCTAssertTrue(Set(built.keys).isSuperset(of: [station, .northGate, .presidentialOffice, .chiangKaiShekMemorialHall]))
        XCTAssertTrue(built.keys.allSatisfy { ![.taipei101, .sunYatSenMemorialHall, .grandHotel, .kaohsiungMainStation].contains($0) })
        let taken = try XCTUnwrap(built[station])
        XCTAssertEqual(triangles(builder.nearMeshes), built.keys.reduce(0) { $0 + $1.model(full: true).indices.count / 3 })
        XCTAssertEqual(triangles(builder.farMeshes), built.keys.reduce(0) { $0 + $1.model(full: false).indices.count / 3 })
        XCTAssertTrue(builder.closeMeshes.isEmpty)
        XCTAssertTrue(builder.keptColours.contains(Self.wall))
        // Its 184 m by 160 m of ground: three 64 m cells each way at least.
        XCTAssertGreaterThanOrEqual(taken.count, 9)
        let middle = builder.point(x: frame.middleX, y: frame.middleY, height: 0)
        XCTAssertTrue(taken.contains(builder.chunk(of: middle)))
        let walls = builder.nearMeshes.values.flatMap(\.vertices).filter { $0.color == Self.wall }
        let xs = walls.map(\.x), zs = walls.map(\.z)
        XCTAssertEqual(((xs.min() ?? 0) + (xs.max() ?? 0)) / 2, middle.x, accuracy: 15)
        XCTAssertEqual(((zs.min() ?? 0) + (zs.max() ?? 0)) / 2, middle.z, accuracy: 15)
    }

    /// Track on the ground through it: not built. Under it, in a tunnel as
    /// the real station's: built.
    func testNotOnTheTrack() throws {
        let world = GameWorld.newGame(anchor: anchor)
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        var builder = builder(world)
        let middle = builder.point(x: frame.middleX, y: frame.middleY, height: 0)
        let line = stride(from: Float(-300), through: 300, by: 2).map { middle + Map3DPoint($0, 0, 30) }
        builder.trackLines = [(line, .surface)]
        XCTAssertNil(builder.addTaipeiLandmarks(frame: frame)[.taipeiMainStation])
        XCTAssertFalse(builder.nearMeshes.values.contains { $0.vertices.contains { $0.color == Self.wall } })
        var under = self.builder(world)
        under.trackLines = [(line, .tunnel)]
        XCTAssertNotNil(under.addTaipeiLandmarks(frame: frame)[.taipeiMainStation])
        // 120 m off, clear of it.
        var beside = self.builder(world)
        beside.trackLines = [(line.map { $0 + Map3DPoint(0, 0, 90) }, .surface)]
        XCTAssertNotNil(beside.addTaipeiLandmarks(frame: frame)[.taipeiMainStation])
    }

    /// A station of the player's beside it is built as Taipei Main
    /// Station, so the station kit would draw its own Taipei there: where
    /// the landmark stands, it draws none.
    func testTheKitsTaipeiGivesWay() throws {
        let start = GameWorld.newGame(anchor: anchor)
        let empty = Map3DScene(world: start)
        let off = Int64(150 * WorldCoordinate.unitsPerMetre), across = Int64(3_000 * WorldCoordinate.unitsPerMetre)
        let y = Int64(empty.originY) - off, x = Int64(empty.originX)
        let world = try newGameLine(through: [PlanPoint(x: x - across, y: y), PlanPoint(x: x, y: y), PlanPoint(x: x + across, y: y)], in: start)
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let (region, originX, originY) = Map3DScene.frame(world: world, focus: nil)
        var builder = Map3DScene.Builder(originX: originX, originY: originY, region: region, world: world, heights: nil)
        let snapshot = world.railwaySnapshot()
        builder.trackCover = Map3DTrackCover(snapshot, builder: &builder)
        _ = builder.addTrack(snapshot)
        builder.addPlatforms(snapshot)
        // The kit's buildings: Taipei's, and the line's two other
        // stations' 3 km off.
        var kit = builder
        let all = kit.addStations(snapshot, frame: frame)
        XCTAssertNotNil(builder.addTaipeiLandmarks(frame: frame)[.taipeiMainStation])
        let others = builder.addStations(snapshot, frame: frame, drawnElsewhere: [.taipei])
        XCTAssertTrue(others.isStrictSubset(of: all))
        let middle = builder.chunk(of: builder.point(x: frame.middleX, y: frame.middleY, height: 0))
        // Within 8 cells (512 m) of the middle's.
        func near(_ cells: Set<Map3DScene.ChunkKey>) -> Bool {
            cells.contains { abs($0.column - middle.column) <= 8 && abs($0.row - middle.row) <= 8 }
        }
        XCTAssertTrue(near(all), "the kit's Taipei, by the middle")
        XCTAssertFalse(near(others))
        // The scene: the landmark's walls, all of them.
        let station = Map3DTaipeiLandmark.taipeiMainStation
        let expected = (station.model(full: true).vertices + station.model(full: false).vertices).filter { $0.color == Self.wall }.count
        XCTAssertEqual(walls(Map3DScene(world: world)), expected)
    }

    private func walls(_ scene: Map3DScene) -> Int {
        scene.chunks.reduce(0) { $0 + ($1.mesh.vertices + $1.far.vertices).filter { $0.color == Self.wall }.count }
    }

    /// The scene draws it on a real-world map, its colours as they are
    /// (not paled), and none on a map of nowhere.
    func testTheSceneTakesIt() {
        let station = Map3DTaipeiLandmark.taipeiMainStation
        let expected = (station.model(full: true).vertices + station.model(full: false).vertices).filter { $0.color == Self.wall }.count
        XCTAssertGreaterThan(expected, 0)
        XCTAssertEqual(walls(Map3DScene(world: GameWorld.newGame(anchor: anchor))), expected)
        XCTAssertEqual(walls(Map3DScene(world: GameWorld.newGame())), 0)
    }
}
