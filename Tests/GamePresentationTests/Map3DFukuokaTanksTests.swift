import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 924: the earlier version's gas holders and water towers where
/// OpenStreetMap maps them in Fukuoka.
final class Map3DFukuokaTanksTests: XCTestCase {
    static var tanks: [Map3DLandmarkRegistration] {
        Map3DLandmarkRegistry.landmarks.filter { $0.id.hasPrefix("fukuoka-gas-holder-") || $0.id.hasPrefix("fukuoka-water-tower-") }
    }

    /// Ten gas holders and seven water towers, each standing where it is
    /// mapped (clear of track), as high as its model, on the outline it
    /// takes the place of.
    func testEachStandsWhereItIsMapped() throws {
        XCTAssertEqual(Self.tanks.filter { $0.id.contains("gas") }.count, 10)
        XCTAssertEqual(Self.tanks.filter { $0.id.contains("water") }.count, 7)
        let world = GameWorld.newOverseasGame(try FukuokaRailwaysTests.ground())
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        for tank in Self.tanks {
            let place = frame.worldPosition(latitude: tank.latitude, longitude: tank.longitude)
            let reach = 60 * Double(WorldCoordinate.unitsPerMetre)
            let region = WorldRegion(minX: place.x - reach, minY: place.y - reach, maxX: place.x + reach, maxY: place.y + reach)
            var builder = Map3DScene.Builder(originX: place.x, originY: place.y, region: region, world: world, heights: nil)
            XCTAssertTrue(builder.addHongKongLandmarks(frame: frame).contains(tank.id), tank.id)
            XCTAssertTrue(builder.underLandmark(builder.point(x: place.x, y: place.y, height: 0)), tank.id)
        }
    }

    /// The colours are the game's own: the yard tanks' white and the
    /// water tank's stand for a gas holder, and a water tower's pale panels
    /// the stations' concrete.
    func testTheirColours() {
        XCTAssertEqual(Map3DFukuokaTanks.gasPalette, [Map3DPalette.tankWhite, Map3DPalette.tankStand])
        XCTAssertEqual(Map3DFukuokaTanks.waterPalette, [Map3DPalette.steel, Map3DPalette.tankStand, Map3DPalette.concrete])
    }
}
