import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 931: M+ and the Hong Kong Palace Museum on Hong Kong's map, in
/// the West Kowloon Cultural District beside Kowloon station.
final class Map3DHKWestKowloonTests: XCTestCase {
    private static let museums = [Map3DHKMPlus.registration, Map3DHKPalaceMuseum.registration]

    /// Both stand with the Tung Chung and Airport Express lines bought
    /// (Kowloon station's tracks are beside them): on their own foot, whole.
    @MainActor
    func testBothStandBesideKowloonStationsLines() throws {
        let session = try HongKongMapTests.hongKong()
        for id in ["hkmtr:TCL", "hkmtr:AEL"] {
            let line = try XCTUnwrap(session.buyableRealLines.first { $0.id == id }, id)
            XCTAssertTrue(session.acquireRealLine(session.realLineOffer(for: line)), "\(id): \(session.message?.text ?? "")")
        }
        let world = session.world
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let metre = Double(WorldCoordinate.unitsPerMetre), reach = 400 * metre
        for museum in Self.museums {
            let place = frame.worldPosition(latitude: museum.latitude, longitude: museum.longitude)
            let region = WorldRegion(minX: place.x - reach, minY: place.y - reach, maxX: place.x + reach, maxY: place.y + reach)
            var builder = Map3DScene.Builder(originX: place.x, originY: place.y, region: region, world: world, heights: session.heights)
            let snapshot = world.railwaySnapshot()
            _ = builder.addTrack(snapshot)
            builder.addPlatforms(snapshot)
            let built = builder.addHongKongLandmarks(frame: frame)
            XCTAssertTrue(built.contains(museum.id), "\(museum.id): \(built)")
            // Nothing else registered stands within the scene but the other
            // museum (M+ and the Palace Museum are 420 m apart).
            let others = built.filter { $0 != museum.id }.compactMap(Map3DLandmarkRegistry.registration)
            XCTAssertTrue(others.allSatisfy { other in Self.museums.contains { $0.id == other.id } }, "\(built)")
        }
    }

    /// The Lands Department's outlines of the two museums (M+'s slab, 3.4 m
    /// north and 1.1 m west of its podium's middle; the Palace Museum's
    /// body, at its registration) are not drawn again under the models.
    func testTheSurveyedMuseumsAreNotDrawnAgain() throws {
        let world = GameWorld.newOverseasGame(try HongKongBaseMapTests.ground())
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let metre = Double(WorldCoordinate.unitsPerMetre), reach = 400 * metre
        for (museum, east, south) in [(Self.museums[0], -1.1, -3.4), (Self.museums[1], 0.0, 0.0)] {
            let place = frame.worldPosition(latitude: museum.latitude, longitude: museum.longitude)
            let region = WorldRegion(minX: place.x - reach, minY: place.y - reach, maxX: place.x + reach, maxY: place.y + reach)
            var builder = Map3DScene.Builder(originX: place.x, originY: place.y, region: region, world: world, heights: nil)
            XCTAssertTrue(builder.addHongKongLandmarks(frame: frame).contains(museum.id), museum.id)
            XCTAssertTrue(builder.underLandmark(builder.point(x: place.x + east * metre, y: place.y + south * metre, height: 0)), museum.id)
            // And a street's width beyond its model, real buildings are drawn.
            let beyond = Double(max(museum.size.x, museum.size.y)) / 2 + 30
            XCTAssertFalse(builder.underLandmark(builder.point(x: place.x + beyond * metre, y: place.y, height: 0)), museum.id)
        }
    }

    /// M+'s slab lies as the Lands Department's outline of it does, its
    /// east end further north (4° anticlockwise), across the podium's middle
    /// (decision 931's later note: revision 2).
    func testMPlusSlabLiesAsSurveyed() {
        let slab = Map3DHKMPlus.registration.model(full: true).vertices.filter { $0.z > 40 }
        XCTAssertFalse(slab.isEmpty)
        let east = slab.filter { $0.x > 40 }.map(\.y), west = slab.filter { $0.x < -40 }.map(\.y)
        let mean = { (values: [Float]) in values.reduce(0, +) / Float(values.count) }
        // Over some 90 m between the two ends' middles, 4° is about 6 m.
        XCTAssertEqual(mean(east) - mean(west), 6.5, accuracy: 2.5)
        // The Lands Department's slab is 1.1 m west and 3.4 m north of the
        // podium's middle (the model's origin).
        let centreX = mean(slab.map(\.x)), centreY = mean(slab.map(\.y))
        XCTAssertLessThanOrEqual(((centreX + 1.1) * (centreX + 1.1) + (centreY - 3.4) * (centreY - 3.4)).squareRoot(), 5,
                                 "the slab where it was surveyed: \(centreX), \(centreY)")
    }
}
