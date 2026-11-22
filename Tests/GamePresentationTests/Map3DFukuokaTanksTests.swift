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
    /// water tank's stand for a gas holder, the depot's steel and the same
    /// stand for a water tower.
    func testTheirColours() {
        XCTAssertEqual(Map3DFukuokaTanks.gasPalette, [Map3DPalette.tankWhite, Map3DPalette.tankStand])
        XCTAssertEqual(Map3DFukuokaTanks.waterPalette, [Map3DPalette.steel, Map3DPalette.tankStand])
    }

    /// Decision 924's later note: a water tower stands on open legs and
    /// cross braces. The earlier version drew each bay between two legs as
    /// one panel textured with braces; given one colour it was a pale
    /// skirt hanging half a metre off the ground. So under the catwalk
    /// everything is the stand's colour and no face is as large as a bay,
    /// near and far, and the legs reach the ground.
    func testAWaterTowerStandsOnOpenLegs() throws {
        for tower in Self.tanks where tower.id.contains("water") {
            for full in [true, false] {
                let mesh = tower.model(full: full)
                let height = try XCTUnwrap(mesh.vertices.map(\.z).max())
                XCTAssertEqual(try XCTUnwrap(mesh.vertices.map(\.z).min()), 0, accuracy: 0.01, tower.id)
                var onTheGround = 0
                for start in stride(from: 0, to: mesh.indices.count, by: 3) {
                    let corners = (0..<3).map { mesh.vertices[Int(mesh.indices[start + $0])] }
                    guard corners.allSatisfy({ $0.z < 0.6 * height }) else { continue }
                    XCTAssertTrue(corners.allSatisfy { $0.color == Map3DPalette.tankStand }, "\(tower.id): a pale face under the catwalk")
                    let (a, b, c) = (corners[0], corners[1], corners[2])
                    let u = Map3DPoint(b.x - a.x, b.y - a.y, b.z - a.z), v = Map3DPoint(c.x - a.x, c.y - a.y, c.z - a.z)
                    let n = u.cross(v)
                    let area = (n.x * n.x + n.y * n.y + n.z * n.z).squareRoot() / 2
                    XCTAssertLessThan(area, 0.02 * height * height, "\(tower.id): a face as large as a bay between two legs")
                    if corners.contains(where: { $0.z < 0.01 }) { onTheGround += 1 }
                }
                XCTAssertGreaterThanOrEqual(onTheGround, 6 * 4, "\(tower.id): six legs on the ground")
            }
        }
    }
}
