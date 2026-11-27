import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 1018 (continued 4): the Chikugo River Lift Bridge, Dazaifu
/// Tenmangu's hall, gate and bridges, the Munakata, Yutoku Inari and Aoi
/// Aso shrines and the Tsujun and Tenmon bridges stand on Fukuoka's map,
/// Dazaifu's precinct outline is not drawn over its hall, and the Tenmon
/// Bridge takes the place of the map's own bridge.
final class Map3DKyushuLandmarksTests: XCTestCase {
    static let landmarks = [Map3DChikugoLiftBridge.registration, Map3DDazaifuHonden.registration, Map3DDazaifuRomon.registration,
                            Map3DDazaifuTaikoBridge.registration, Map3DMunakataTaisha.registration, Map3DYutokuInari.registration,
                            Map3DAoiAsoShrine.registration, Map3DTsujunBridge.registration, Map3DTenmonBridge.registration,
                            // Decision 1018 (continued 5).
                            Map3DYoshinogariSanctuary.registration, Map3DYoshinogariWatchtower.registration]

    func scene(round landmark: Map3DLandmarkRegistration, half: Double = 400)
        throws -> (builder: Map3DScene.Builder, frame: RealWorldFrame, region: WorldRegion, ground: OverseasGround) {
        let ground = try FukuokaRailwaysTests.ground()
        var world = GameWorld.newOverseasGame(ground)
        try world.mapGround()
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let metre = Double(WorldCoordinate.unitsPerMetre)
        let at = frame.worldPosition(latitude: landmark.latitude, longitude: landmark.longitude)
        let region = WorldRegion(minX: at.x - half * metre, minY: at.y - half * metre, maxX: at.x + half * metre, maxY: at.y + half * metre)
        return (Map3DScene.Builder(originX: at.x, originY: at.y, region: region, world: world, heights: ground.heights), frame, region, ground)
    }

    /// Each is built where it stands, on its map's ground, no lower than
    /// the lowest ground under it.
    func testTheyStandOnFukuokasMap() throws {
        for landmark in Self.landmarks {
            XCTAssertEqual(landmark.map, "fukuoka")
            var (builder, frame, _, _) = try scene(round: landmark)
            XCTAssertTrue(builder.addHongKongLandmarks(frame: frame).contains(landmark.id), landmark.id)
            let feet = builder.nearMeshes.values.flatMap(\.vertices).filter { hypot($0.x, $0.z) < 20 }.map(\.y)
            XCTAssertGreaterThan(feet.max() ?? 0, (feet.min() ?? 0) + 5, "\(landmark.id) stands up")
        }
    }

    /// OpenStreetMap draws Dazaifu's hall, cloister and gate as one
    /// outline 78 m by 50 m whose middle is in the courtyard, which the
    /// hall's model does not cover: it is not drawn (it counts as built),
    /// and no other building is left out with it.
    func testDazaifusPrecinctOutlineIsNotDrawnOverItsHall() throws {
        let hall = Map3DDazaifuHonden.registration
        var (builder, frame, _, _) = try scene(round: hall)
        XCTAssertTrue(builder.addHongKongLandmarks(frame: frame).contains(hall.id))
        let metre = Double(WorldCoordinate.unitsPerMetre)
        let buildings = try FukuokaBuildingsTests.allBuildings(latitude: hall.latitude, longitude: hall.longitude, reach: 80)
        func size(_ building: Map3DFootprints.Building) -> Double {
            let xs = building.rings[0].map(\.x), ys = building.rings[0].map(\.y)
            return (xs.max()! - xs.min()!) * (ys.max()! - ys.min()!) / (metre * metre)
        }
        func replaced(_ building: Map3DFootprints.Building) -> Bool {
            let ring = building.rings[0]
            let middle = builder.point(x: ring.reduce(0) { $0 + $1.x } / Double(ring.count), y: ring.reduce(0) { $0 + $1.y } / Double(ring.count), height: 0)
            return builder.state.landmarks.replacedPlots.contains { $0.minX <= middle.x && middle.x <= $0.maxX && $0.minZ <= middle.z && middle.z <= $0.maxZ }
        }
        let precinct = try XCTUnwrap(buildings.max { size($0) < size($1) })
        XCTAssertGreaterThan(size(precinct), 3_000, "the precinct's outline")
        XCTAssertTrue(replaced(precinct))
        XCTAssertEqual(buildings.filter(replaced).count, 1, "only the precinct")
    }

    /// The Tenmon Bridge's road is 43.24 m over the sea it stands in, and
    /// the map's own raised road over the strait is left out under it.
    func testTheTenmonBridgeTakesTheMapsBridge() throws {
        let bridge = Map3DTenmonBridge.registration
        let deck = try XCTUnwrap(bridge.deck)
        let ends = try XCTUnwrap(Map3DScene.Builder.deckEnds(of: bridge.model(full: true), deck: deck))
        XCTAssertGreaterThan(hypot(ends[0].x - ends[1].x, ends[0].y - ends[1].y), 500, "the deck's two ends")
        var (builder, frame, region, ground) = try scene(round: bridge)
        XCTAssertTrue(builder.addHongKongLandmarks(frame: frame).contains(bridge.id))
        let road = builder.nearMeshes.values.flatMap(\.vertices).filter { $0.color == Map3DPalette.dark && hypot($0.x, $0.z) < 300 }
        XCTAssertEqual(try XCTUnwrap(road.map(\.y).max()), deck, accuracy: 0.5, "its road over the sea")

        let at = frame.worldPosition(latitude: bridge.latitude, longitude: bridge.longitude)
        let tiles = try BaseMapTiles(data: Data(contentsOf: HongKongBaseMapTests.taiwan, options: .alwaysMapped), cities: ground.baseMaps)
        let map = Map3DBaseMap(tiles: tiles, frame: frame, region: region, originX: at.x, originY: at.y)
        // Along its axis (+x at 109.7°: east and a third as far south in
        // the scene), within its length: the trunk road's bridge, not the
        // expressway's Tenjo Bridge 100 m to the south-west.
        let axis = (x: sin(109.7 * Double.pi / 180), z: -cos(109.7 * Double.pi / 180))
        func onIt(_ points: [Map3DBaseMap.Point]) -> Bool {
            points.allSatisfy { point in
                let along = point.x * axis.x + point.z * axis.z
                let across = point.x * axis.z - point.z * axis.x
                return abs(along) < 270 && abs(across) < 15
            }
        }
        XCTAssertEqual(map.roads.filter { $0.bridgeLevel > 0 && onIt($0.points) }.count, 1, "the map's bridge over the strait")
        let left = map.leavingOut(builder.landmarkDecks(frame: frame))
        XCTAssertTrue(left.roads.filter { $0.bridgeLevel > 0 && onIt($0.points) }.isEmpty)
        XCTAssertEqual(left.roads.filter { $0.bridgeLevel > 0 }.count, map.roads.filter { $0.bridgeLevel > 0 }.count - 1, "the Tenjo Bridge stays")
        XCTAssertEqual(left.roads.filter { $0.bridgeLevel == 0 }.count, map.roads.filter { $0.bridgeLevel == 0 }.count, "the roads on the ground stay")
    }
}
