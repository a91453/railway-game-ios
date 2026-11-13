@testable import GamePresentation
import XCTest

/// The base map's smallest lakes (fountains, ornamental pools, ponds on
/// podium roofs) showed in 3D as loose blue triangles on the ground: one
/// of 113 m² on Kowloon Station's plaza, and many through Taipei. A lake
/// under ``Map3DBaseMap/smallestLake`` wholly inside its tile is left out;
/// one cut at the tile's edge is a piece of a bigger one and stays.
final class Map3DSmallLakeTests: XCTestCase {
    private typealias P = Map3DBaseMap.Point
    private static let tile = Map3DBaseMap.Bounds(minX: 0, minZ: 0, maxX: 2000, maxZ: 2000)

    private static func square(x: Double, z: Double, side: Double) -> [P] {
        [P(x: x, z: z), P(x: x + side, z: z), P(x: x + side, z: z + side), P(x: x, z: z + side)]
    }

    func testAFountainInsideItsTileIsLeftOut() {
        XCTAssertTrue(Map3DBaseMap.isSpeck([Self.square(x: 900, z: 900, side: 11)], in: Self.tile), "121 m²")
        XCTAssertTrue(Map3DBaseMap.isSpeck([Self.square(x: 900, z: 900, side: 22)], in: Self.tile), "484 m²")
    }

    func testAPondBigEnoughToReadStays() {
        XCTAssertFalse(Map3DBaseMap.isSpeck([Self.square(x: 900, z: 900, side: 23)], in: Self.tile), "529 m²")
        XCTAssertFalse(Map3DBaseMap.isSpeck([Self.square(x: 900, z: 900, side: 200)], in: Self.tile))
    }

    func testALakesHolesCountAgainstIt() {
        // 30 × 30 less a 25 × 25 island: 275 m² of water.
        let rings = [Self.square(x: 900, z: 900, side: 30), Self.square(x: 902, z: 902, side: 25)]
        XCTAssertTrue(Map3DBaseMap.isSpeck(rings, in: Self.tile))
    }

    func testAPieceCutAtTheTilesEdgeStays() {
        // A sliver of a big lake reaching into the tile's buffer.
        XCTAssertFalse(Map3DBaseMap.isSpeck([Self.square(x: 1995, z: 900, side: 10)], in: Self.tile))
        XCTAssertFalse(Map3DBaseMap.isSpeck([Self.square(x: -5, z: -5, side: 8)], in: Self.tile))
    }
}
