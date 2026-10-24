import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 393: the base map's farmland, which the bundled tiles had none
/// of, so in 3D the land between the stations, where the game reads in
/// no zones, was the bare ground (TestFlight 86.1, the owner's iPhone: 「地有
/// 一大片白」).
final class Map3DFarmlandTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private static let tiles: Result<BaseMapTiles, Error> = Result {
        try BaseMapTiles(data: Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/BaseMap/taiwan.pmtiles"), options: .alwaysMapped))
    }

    func testTheTilesFarmlandIsACover() {
        XCTAssertEqual(Map3DBaseMap.cover(layer: "landcover", class: "farmland"), .farmland)
        XCTAssertEqual(Map3DBaseMap.cover(layer: "landcover", class: "wood"), .wood)
        XCTAssertNil(Map3DBaseMap.cover(layer: "landcover", class: "ice"))
        XCTAssertEqual(Map3DPalette.cover(.farmland), Map3DPalette.farm, "decision 370's farm")
    }

    func testFarmlandLiesUnderEveryOtherCoverAndTheWaterUnderTheSidewalks() {
        typealias B = Map3DScene.Builder
        // A city lot's open ground lies at 0.02 m, which the ground hides
        // from afar; farmland stands a cover's step over it.
        XCTAssertEqual(B.lift(of: .farmland), 0.035, accuracy: 0.0001)
        for cover in Map3DBaseMap.Cover.allCases where cover != .farmland {
            XCTAssertLessThan(B.lift(of: .farmland), B.lift(of: cover))
        }
        XCTAssertLessThan(B.lift(of: .water), B.sidewalkLift)
    }

    func testFarmlandIsLaidButTakesNoLot() {
        let world = GameWorld.newGame()
        var builder = Map3DScene.Builder(originX: 0, originY: 0, region: WorldRegion(bounds: world.bounds), world: world)
        typealias P = Map3DBaseMap.Point
        let field = [P(x: 0, z: 0), P(x: 200, z: 0), P(x: 200, z: 200), P(x: 0, z: 200)]
        var taken = Set<Map3DScene.ChunkKey>()
        builder.addArea(Map3DBaseMap.Area(cover: .farmland, rings: [field], bounds: Map3DBaseMap.Bounds(minX: -1e4, minZ: -1e4, maxX: 1e4, maxZ: 1e4)),
                        taking: &taken)
        XCTAssertTrue(taken.isEmpty, "the city's farm houses still stand on it")
        let vertices = builder.meshes.values.flatMap(\.vertices)
        XCTAssertFalse(vertices.isEmpty)
        XCTAssertTrue(vertices.allSatisfy { $0.color == Map3DPalette.farm })
    }

    func testThe2DMapDrawsFarmlandUnderTheOtherCover() throws {
        for (dark, colour) in [(false, "#F1E6C8"), (true, "#5A5236")] {
            let ids = BaseMapStyle.layers(dark ? .dark : .light).compactMap { $0["id"] as? String }
            let farmland = try XCTUnwrap(ids.firstIndex(of: "landcover-farmland"))
            XCTAssertLessThan(farmland, try XCTUnwrap(ids.firstIndex(of: "landcover-wood")))
            XCTAssertEqual((dark ? BaseMapStyle.Colors.dark : .light).farmland, colour, "the 2D map's own farm lots'")
        }
    }

    func testTheBundledTilesHaveTheFieldsAlongTheHighSpeedRail() throws {
        // 4 × 4 tiles at the 3D map's zoom (some 9 × 9 km) round three
        // stations on the plain; on origin/main none of it was farmland.
        let tiles = try Self.tiles.get()
        let zoom = BaseMapTiles.zoom, n = Double(1 << zoom)
        for (name, latitude, longitude, least) in [("雲林", 23.736, 120.417, 0.3), ("嘉義", 23.459, 120.323, 0.3), ("彰化", 23.874, 120.574, 0.05)] {
            let x = Int((longitude + 180) / 360 * n), radians = latitude * .pi / 180
            let y = Int((1 - log(tan(radians) + 1 / cos(radians)) / .pi) / 2 * n)
            var share = 0.0
            for column in (x - 2)..<(x + 2) {
                for row in (y - 2)..<(y + 2) {
                    guard let bytes = try tiles.archive.tile(zoom: zoom, x: column, y: row),
                          let layer = try VectorTile(bytes, layers: ["landcover"]).layers["landcover"]
                    else { continue }
                    for feature in layer.features where feature.string("class") == "farmland" {
                        for polygon in feature.polygons {
                            share += Double(polygon.map { VectorTile.Feature.signedArea($0) }.reduce(0, +)) / Double(layer.extent * layer.extent) / 16
                        }
                    }
                }
            }
            XCTAssertGreaterThan(share, least, name)
        }
    }
}
