import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 938: the Tian Tan Buddha and Po Lin Monastery on Hong Kong's
/// map, on the Lands Department's ground at Ngong Ping: both built, clear
/// of the cable car, nowhere afloat.
final class Map3DTianTanBuddhaTests: XCTestCase {
    func testTheyStandOnNgongPingsGround() throws {
        let ground = try HongKongBaseMapTests.ground()
        let heights = try XCTUnwrap(ground.heights)
        var world = GameWorld.newOverseasGame(ground)
        try world.mapGround()
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        for landmark in [Map3DTianTanBuddha.registration, Map3DPoLinMonastery.registration] {
            let place = frame.worldPosition(latitude: landmark.latitude, longitude: landmark.longitude)
            let metre = Double(WorldCoordinate.unitsPerMetre), reach = 120 * metre
            let region = WorldRegion(minX: place.x - reach, minY: place.y - reach, maxX: place.x + reach, maxY: place.y + reach)
            var builder = Map3DScene.Builder(originX: place.x, originY: place.y, region: region, world: world, heights: heights)
            XCTAssertEqual(builder.addHongKongLandmarks(frame: frame), [landmark.id])
            let near = builder.nearMeshes.values.flatMap(\.vertices)
            XCTAssertEqual(near.count, landmark.model(full: true).vertices.count)
            let foot = try XCTUnwrap(near.map(\.y).min()), top = try XCTUnwrap(near.map(\.y).max())
            XCTAssertEqual(top - foot, landmark.size.z, accuracy: 0.01)
            // The ground under the corners of its footprint: its foot on
            // the lowest, so no side stands in the air.
            let xs = near.map(\.x), zs = near.map(\.z)
            let under = [(xs.min()!, zs.min()!), (xs.max()!, zs.min()!), (xs.min()!, zs.max()!), (xs.max()!, zs.max()!)]
                .map { builder.drawnGround(x: $0.0, z: $0.1) }
            XCTAssertEqual(foot, under.min()!, accuracy: 0.01, "\(landmark.id): \(under)")
            // Ngong Ping's plateau, some 440 to 480 m up.
            XCTAssertTrue((430...490).contains(foot), "\(landmark.id): \(foot)")
        }
    }

    /// The Buddha without his long stairs (decision 938): nothing of the
    /// model reaches past his lowest terrace and its short steps, and his
    /// raised right hand is on the side it is on in the photographs (his
    /// own right, the south-east as he faces north-east).
    func testTheBuddhaFacesNorthEastWithoutTheLongStairs() {
        let model = Map3DTianTanBuddha.registration.model(full: true)
        XCTAssertTrue(model.vertices.allSatisfy { hypot($0.x, $0.y) <= 22.5 })
        // The short steps at the foot of the terraces, towards the north-east.
        let steps = model.vertices.filter { $0.z < 0.3 }
        XCTAssertFalse(steps.isEmpty)
        XCTAssertTrue(steps.allSatisfy { $0.x > 0 && $0.y > 0 }, "the steps' foot to the north-east")
        // The raised hand: the bronze furthest from his axis at shoulder
        // height, on his right.
        let bronze = Map3DPalette.counters[1]
        let hand = model.vertices.filter { $0.color == bronze && $0.z > 23 && $0.z < 26.5 }
            .max { hypot($0.x, $0.y) < hypot($1.x, $1.y) }
        // North-east turned a quarter clockwise is south-east: his right.
        XCTAssertNotNil(hand)
        if let hand { XCTAssertGreaterThan(hand.x * 0.734 - hand.y * 0.679, 5, "\(hand.x), \(hand.y)") }
    }
}
