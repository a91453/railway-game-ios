import XCTest
import Foundation
@testable import GamePresentation
import GameCore

/// RAMP-GRADE (decision 822, later note of 2026-11-27): the owner's
/// Fukuoka screenshots showed the urban expressway's interchange ramps
/// far too steep. Round 天神 half of the link roads' bridges came down
/// at 12–23 %: a ramp's share of its height and its lift to a higher
/// level (or its end's dip) came down together. ``Map3DRoadBridges``
/// now keeps every bridge piece there within 9 % over any 10 m.
final class Map3DRoadRampGradeTests: XCTestCase {
    typealias Point = Map3DBaseMap.Point

    func testTenjinsExpresswayBridgesAreNoSteeperThanNinePercent() throws {
        let ground = try OverseasGround(city: .fukuoka, pack: XCTUnwrap(HongKongRailwaysTests.pack(.fukuoka)))
        let tiles = try BaseMapTiles(data: Data(contentsOf: HongKongBaseMapTests.taiwan, options: .alwaysMapped), cities: ground.baseMaps)
        var world = GameWorld.newOverseasGame(ground, wholeMap: true)
        try world.mapGround()
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let at = frame.worldPosition(latitude: 33.5913, longitude: 130.3989)
        let metre = Double(WorldCoordinate.unitsPerMetre), half = 700.0
        let region = WorldRegion(minX: at.x - half * metre, minY: at.y - half * metre, maxX: at.x + half * metre, maxY: at.y + half * metre)
        let map = Map3DBaseMap(tiles: tiles, frame: frame, region: region, originX: at.x, originY: at.y)
        var builder = Map3DScene.Builder(originX: at.x, originY: at.y, region: region, world: world, heights: ground.heights)
        builder.addGround()
        builder.state.roadBridges = builder.bridgeDecks(of: map, frame: frame)
        let bridges = builder.state.roadBridges
        XCTAssertGreaterThan(bridges.pieces.filter(\.isRamp).count, 20, "天神's interchanges have link roads' bridges")
        var steep: [String] = []
        for (number, piece) in bridges.pieces.enumerated() {
            // The height of its road every 2 m along it.
            var heights: [(along: Double, height: Float)] = []
            var run = 0.0
            for (a, b) in zip(piece.points, piece.points.dropFirst()) {
                let length = ((b.x - a.x) * (b.x - a.x) + (b.z - a.z) * (b.z - a.z)).squareRoot()
                var s = 0.0
                while s < length {
                    let p = Point(x: a.x + (b.x - a.x) * s / length, z: a.z + (b.z - a.z) * s / length)
                    heights.append((run + s, builder.drawnGround(x: Float(p.x), z: Float(p.z)) + builder.pieceRise(bridges, piece: number, at: p)))
                    s += 2
                }
                run += length
            }
            var j = 0
            for i in heights.indices {
                j = max(j, i + 1)
                while j < heights.count, heights[j].along - heights[i].along < 10 { j += 1 }
                guard j < heights.count else { break }
                let slope = abs(heights[j].height - heights[i].height) / Float(heights[j].along - heights[i].along)
                if slope > 0.09 {
                    steep.append("piece \(number) at \(Int(piece.points[0].x)),\(Int(piece.points[0].z)), \(Int(heights[i].along)) m along: \(Int(slope * 100)) %")
                    break
                }
            }
        }
        XCTAssertEqual(steep, [], "bridges steeper than 9 % over 10 m")
    }
}
