import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 1033: Ōmura depot's sheds and office, registered landmarks on
/// Japan's map beside the Nishi-Kyushu Shinkansen.
final class Map3DOmuraDepotTests: XCTestCase {
    private static let buildings = [Map3DOmuraDepotSheds.registration, Map3DOmuraDepotOffice.registration]

    /// Each one's turned rectangle holds its whole model, and is smaller
    /// than its box east and north (so the line beside it is not taken
    /// for track through it).
    func testTheBodiesHoldTheModels() throws {
        for building in Self.buildings {
            let corners = try XCTUnwrap(building.body, building.id)
            XCTAssertEqual(corners.count, 4)
            let a = corners[0], b = corners[1], d = corners[3]
            let u = (x: b.x - a.x, y: b.y - a.y), v = (x: d.x - a.x, y: d.y - a.y)
            let uu = u.x * u.x + u.y * u.y, vv = v.x * v.x + v.y * v.y
            XCTAssertEqual((u.x * v.x + u.y * v.y) / (uu * vv).squareRoot(), 0, accuracy: 0.001, "\(building.id): a rectangle")
            for vertex in building.model(full: true).vertices {
                let p = (x: vertex.x - a.x, y: vertex.y - a.y)
                let s = (p.x * u.x + p.y * u.y) / uu, t = (p.x * v.x + p.y * v.y) / vv
                XCTAssertTrue((-0.001...1.001).contains(s) && (-0.001...1.001).contains(t), "\(building.id): \(vertex.x), \(vertex.y)")
            }
            XCTAssertLessThan(uu.squareRoot() * vv.squareRoot(), building.size.x * building.size.y, building.id)
        }
    }

    /// Both stand with the Nishi-Kyushu Shinkansen bought, its main line
    /// running by the sheds' east side.
    @MainActor
    func testBothStandWithTheLineBought() throws {
        let session = try FukuokaRailwaysTests.fukuoka(start: 3)
        let real = try XCTUnwrap(session.buyableRealLines.first { $0.id == NishiKyushuShinkansenTests.id })
        XCTAssertTrue(session.acquireRealLine(session.realLineOffer(for: real)), session.message?.text ?? "")
        let world = session.world
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let metre = Double(WorldCoordinate.unitsPerMetre), reach = 600 * metre
        let place = frame.worldPosition(latitude: Map3DOmuraDepotSheds.registration.latitude, longitude: Map3DOmuraDepotSheds.registration.longitude)
        let region = WorldRegion(minX: place.x - reach, minY: place.y - reach, maxX: place.x + reach, maxY: place.y + reach)
        var builder = Map3DScene.Builder(originX: place.x, originY: place.y, region: region, world: world, heights: session.heights)
        let snapshot = world.railwaySnapshot()
        _ = builder.addTrack(snapshot)
        builder.addPlatforms(snapshot)
        XCTAssertFalse(builder.state.track.trackLines.isEmpty, "the line runs through the scene")
        let built = builder.addHongKongLandmarks(frame: frame)
        for building in Self.buildings { XCTAssertTrue(built.contains(building.id), "\(building.id): \(built)") }
    }
}
