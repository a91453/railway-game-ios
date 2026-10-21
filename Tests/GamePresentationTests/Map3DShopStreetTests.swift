@testable import GameCore
@testable import GamePresentation
import XCTest

/// ARCHITECTURE decision 322: the station-front shop street.
final class Map3DShopStreetTests: XCTestCase {
    private static let station = StationID(rawValue: 7)

    /// A builder with one platform 120 m long along x, on the right (+z)
    /// of its track at z 0, and a through track at z −5 (as
    /// `Map3DStationsTests` lays it), and `roads` (their z) along x.
    private func builder(roads: [Float] = []) -> Map3DScene.Builder {
        var builder = Map3DScene.Builder(originX: 0, originY: 0, region: WorldRegion(minX: -64_000, minY: -64_000, maxX: 64_000, maxY: 64_000),
                                         world: GameWorld.newGame())
        func line(_ z: Float) -> [Map3DPoint] { stride(from: Float(-60), through: 60, by: 2).map { Map3DPoint($0, Map3DScene.railLift, z) } }
        builder.laidPlatforms = [Map3DScene.Builder.LaidPlatform(station: Self.station, line: line(0), offset: 3.5, width: 3.2, structure: .surface)]
        builder.trackLines = [(line(0), .surface), (line(-5), .surface)]
        builder.roadLines = roads.map { z in ([Map3DPoint(-300, 0, z), Map3DPoint(300, 0, z)], 5) }
        return builder
    }

    /// The awnings' cream stripes, one group to a shop.
    private func cream(_ meshes: [Map3DScene.ChunkKey: Map3DMesh]) -> [Map3DVertex] {
        meshes.values.flatMap(\.vertices).filter { $0.color == Map3DPalette.awningCream }
    }

    private var creamPerShop: Int {
        Map3DScene.Builder.shop(seed: 1, index: 0, lane: 0, tall: false).mesh.vertices.filter { $0.color == Map3DPalette.awningCream }.count
    }

    func testShopsLineTheStationsPlazaOnItsSideOfTheTrack() {
        var b = builder()
        let cells = b.addStations(GameWorld.newGame().railwaySnapshot(), frame: nil)
        let stripes = cream(b.nearMeshes)
        let shops = stripes.count / creamPerShop
        XCTAssertGreaterThanOrEqual(shops, 4, "a regional station has a shop street")
        XCTAssertLessThanOrEqual(shops, 12)
        // On the building's side, clear of the platform (to 5.1 m), on its
        // plaza's cells.
        XCTAssertGreaterThan(stripes.map(\.z).min() ?? 0, 6)
        XCTAssertTrue(stripes.allSatisfy { cells.contains(b.chunk(of: Map3DPoint($0.x, 0, $0.z))) })
        // Beside the building, and across its forecourt facing it.
        let sides = Set(stripes.map { $0.x > 0 })
        XCTAssertEqual(sides.count, 2)
        // Far off a box each.
        XCTAssertFalse(cream(b.farMeshes).contains { _ in true })
        XCTAssertFalse(b.streetLife.spots.filter { $0.kind == .shops }.isEmpty)
    }

    func testNoShopStandsOnARoad() {
        var plain = builder()
        _ = plain.addStations(GameWorld.newGame().railwaySnapshot(), frame: nil)
        // A road through the row across the forecourt.
        let across = cream(plain.nearMeshes).map(\.z).max() ?? 0
        var b = builder(roads: [across])
        _ = b.addStations(GameWorld.newGame().railwaySnapshot(), frame: nil)
        let stripes = cream(b.nearMeshes)
        XCTAssertFalse(stripes.isEmpty)
        XCTAssertTrue(stripes.allSatisfy { abs($0.z - across) > 5 }, "the road and its pavement stay clear")
        // The shops that stood there now stand farther along.
        XCTAssertNotEqual(Set(stripes.map(\.x)), Set(cream(plain.nearMeshes).map(\.x)))
    }

    func testTheNearestShopIsTallestWithARooftopSignAndDownlights() {
        let tall = Map3DScene.Builder.shop(seed: 3, index: 0, lane: 0, tall: true)
        let lit = tall.mesh.vertices.filter { $0.glows }
        XCTAssertTrue(lit.contains { $0.color == Map3DProp.lampLight }, "the downlights")
        XCTAssertGreaterThan(lit.map(\.y).max() ?? 0, tall.height + 1, "the rooftop sign")
        for index: Int32 in 1...20 {
            let shop = Map3DScene.Builder.shop(seed: 3, index: index, lane: Int(index), tall: false)
            XCTAssertLessThan(shop.height, tall.height)
            XCTAssertFalse(shop.mesh.vertices.contains { $0.glows && $0.color == Map3DProp.lampLight })
            // The sign is lit at night.
            XCTAssertTrue(shop.mesh.vertices.contains { $0.glows })
            XCTAssertLessThan(shop.mesh.indices.count / 3, 700)
        }
    }

    func testNeighboursInARowAreNeverAlike() {
        for seed: Int32 in [0, 1, 7, 12_345] {
            for lane in -8..<8 {
                XCTAssertNotEqual(Map3DScene.Builder.shopColour(seed: seed, lane: lane), Map3DScene.Builder.shopColour(seed: seed, lane: lane + 1))
            }
        }
    }

    func testALandmarkKeepsItsOwnForecourt() throws {
        let landmark = try XCTUnwrap(Map3DStationKit.stations.first { $0.isLandmark })
        var b = builder()
        b.addShopStreet(landmark, centre: Map3DPoint(0, 0, 40), forward: Map3DPoint(0, 0, 1), depth: 40, wide: 60,
                        cells: Set((-4...4).flatMap { c in (-4...4).map { Map3DScene.ChunkKey(column: c, row: $0) } }))
        XCTAssertTrue(b.nearMeshes.isEmpty)
        XCTAssertTrue(b.farMeshes.isEmpty)
    }
}
