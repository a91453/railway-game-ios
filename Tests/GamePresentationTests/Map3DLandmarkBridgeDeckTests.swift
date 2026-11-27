import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// BRIDGE-LANDMARK-DECK: a landmark road bridge
/// (``Map3DLandmarkRegistration/deck``) stands with its road level with the
/// drawn ground at its ends, and the real map's own bridge under it is
/// left out (``Map3DBaseMap/leavingOut(_:)``).
final class Map3DLandmarkBridgeDeckTests: XCTestCase {
    /// The owner's IMG_5675 (2026-11-27): Rovaniemi's Lumberjack's Candle
    /// stood on the lowest ground under its corners, its road 4–5 m over
    /// the banks' roads, the map's own bridge drawn under it. Its road now
    /// meets the banks, and the map's bridge is gone.
    func testTheCandleBridgesRoadMeetsTheBanks() throws {
        let ground = try OverseasGround(city: .rovaniemi, pack: XCTUnwrap(HongKongRailwaysTests.pack(.rovaniemi)))
        var world = GameWorld.newOverseasGame(ground)
        try world.mapGround()
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let bridge = Map3DRovaniemiCandleBridge.registration
        let deck = try XCTUnwrap(bridge.deck)
        let at = frame.worldPosition(latitude: bridge.latitude, longitude: bridge.longitude)
        let metre = Double(WorldCoordinate.unitsPerMetre), half = 400.0
        let region = WorldRegion(minX: at.x - half * metre, minY: at.y - half * metre, maxX: at.x + half * metre, maxY: at.y + half * metre)
        var builder = Map3DScene.Builder(originX: at.x, originY: at.y, region: region, world: world, heights: ground.heights)
        let ends = try XCTUnwrap(Map3DScene.Builder.deckEnds(of: bridge.model(full: true), deck: deck))
        XCTAssertGreaterThan(hypot(ends[0].x - ends[1].x, ends[0].y - ends[1].y), 290, "the deck's two ends")
        let banks = ends.map { builder.drawnGround(x: $0.x, z: -$0.y) }
        XCTAssertTrue(builder.addHongKongLandmarks(frame: frame).contains(bridge.id))
        let road = builder.nearMeshes.values.flatMap(\.vertices).filter { $0.color == Map3DPalette.arcade && hypot($0.x, $0.z) < 170 }
        let top = try XCTUnwrap(road.map(\.y).max())
        for bank in banks { XCTAssertEqual(top, bank, accuracy: 1.5, "its road against a bank's ground") }

        let tiles = try BaseMapTiles(data: Data(contentsOf: HongKongBaseMapTests.taiwan, options: .alwaysMapped), cities: ground.baseMaps)
        let map = Map3DBaseMap(tiles: tiles, frame: frame, region: region, originX: at.x, originY: at.y)
        func near(_ points: [Map3DBaseMap.Point]) -> Bool {
            hypot((points[0].x + points[points.count - 1].x) / 2, (points[0].z + points[points.count - 1].z) / 2) < 100
        }
        XCTAssertGreaterThanOrEqual(map.roads.filter { $0.bridgeLevel > 0 && near($0.points) }.count, 2, "the map's bridge over the Kemijoki")
        let left = map.leavingOut(builder.landmarkDecks(frame: frame))
        XCTAssertTrue(left.roads.filter { $0.bridgeLevel > 0 && near($0.points) }.isEmpty)
        XCTAssertTrue(left.bridges.filter { near($0.points) }.isEmpty)
        XCTAssertEqual(left.roads.filter { $0.bridgeLevel == 0 }.count, map.roads.filter { $0.bridgeLevel == 0 }.count, "the roads on the ground stay")
        XCTAssertLessThan(map.roads.count - left.roads.count, 6, "only the bridge under it")
    }
}
