import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 913: the Peak Tower on Hong Kong's map, on the Lands
/// Department's ground: its plaza floor on the ground at its middle, its
/// plinth reaching down to the ground on the hillside, nowhere afloat.
final class Map3DPeakTowerTests: XCTestCase {
    func testItStandsOnThePeaksGround() throws {
        let ground = try HongKongBaseMapTests.ground()
        let heights = try XCTUnwrap(ground.heights)
        // On the pack's ground, as the launcher starts the map.
        var world = GameWorld.newOverseasGame(ground)
        try world.mapGround()
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let tower = Map3DPeakTower.registration
        let place = frame.worldPosition(latitude: tower.latitude, longitude: tower.longitude)
        let metre = Double(WorldCoordinate.unitsPerMetre), reach = 400 * metre
        let region = WorldRegion(minX: place.x - reach, minY: place.y - reach, maxX: place.x + reach, maxY: place.y + reach)
        var builder = Map3DScene.Builder(originX: place.x, originY: place.y, region: region, world: world, heights: heights)
        XCTAssertEqual(builder.addHongKongLandmarks(frame: frame), [tower.id])
        let near = builder.nearMeshes.values.flatMap(\.vertices)
        XCTAssertEqual(near.count, tower.model(full: true).vertices.count)
        let foot = try XCTUnwrap(near.map(\.y).min()), top = try XCTUnwrap(near.map(\.y).max())
        XCTAssertEqual(top - foot, tower.size.z, accuracy: 0.01)
        // The ground under its footprint's corners and middle.
        let xs = near.map(\.x), zs = near.map(\.z)
        let (minX, maxX, minZ, maxZ) = (xs.min()!, xs.max()!, zs.min()!, zs.max()!)
        let under = [(minX, minZ), (maxX, minZ), (minX, maxZ), (maxX, maxZ), ((minX + maxX) / 2, (minZ + maxZ) / 2)]
            .map { builder.drawnGround(x: $0.0, z: $0.1) }
        // The Peak's plaza 396 m up (the Lands Department's model averages
        // each cell, so a little either way).
        let plaza = foot + tower.sink
        XCTAssertEqual(plaza, under[4], accuracy: 0.01, "the plaza floor on the ground at its middle")
        XCTAssertEqual(plaza, 396, accuracy: 10, "\(under)")
        XCTAssertLessThanOrEqual(foot, under.min()! + 0.01, "its foot reaches the hillside's ground: \(under)")
    }
}
