import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 835: Hong Kong's map pack has its own land cover
/// (`landcover.dat`, the Planning Department's land use grid folded into
/// decision 811's eight covers, `tools/hk-map/build_hk_landcover.py`), so
/// the 3D map tints its countryside and plants its woods as Taiwan's.
@MainActor
final class HongKongLandCoverTests: XCTestCase {
    private static let ground: Result<OverseasGround, Error> = Result { try HongKongMapTests.ground() }

    private func grid() throws -> LandCoverGrid {
        try XCTUnwrap(try Self.ground.get().landCover, "the pack's landcover.dat")
    }

    /// The country parks' woods, Lantau's grassy tops, Tai O's fields and
    /// Mai Po's ponds, the towns' built-up land; the sea and the
    /// reservoirs (OpenStreetMap's water) are not known.
    func testTheFileKnowsHongKongsGround() throws {
        let grid = try grid()
        XCTAssertEqual(grid.cover(latitude: 22.400, longitude: 114.300), .forest, "Sai Kung")
        XCTAssertEqual(grid.cover(latitude: 22.2516, longitude: 113.9200), .grassland, "Lantau Peak")
        XCTAssertEqual(grid.cover(latitude: 22.252, longitude: 113.862), .cropland, "Tai O")
        XCTAssertEqual(grid.cover(latitude: 22.3193, longitude: 114.1694), .builtUp, "Mong Kok")
        XCTAssertEqual(grid.cover(latitude: 22.310, longitude: 113.915), .builtUp, "the airport")
        XCTAssertNil(grid.cover(latitude: 22.2880, longitude: 114.1720), "Victoria Harbour")
        XCTAssertNil(grid.cover(latitude: 22.465, longitude: 114.255), "Plover Cove Reservoir")
        XCTAssertNil(grid.cover(latitude: 25.0478, longitude: 121.5170), "Taipei, off the grid")
        // Most of the land is countryside: woods, scrub and grass.
        var counts: [LandCoverGrid.Cover: Int] = [:]
        var reader = LandCoverGrid.Reader(grid)
        for latitude in stride(from: 22.16, to: 22.55, by: 0.005) {
            for longitude in stride(from: 113.84, to: 114.44, by: 0.005) {
                if let cover = reader.cover(latitude: latitude, longitude: longitude) { counts[cover, default: 0] += 1 }
            }
        }
        let land = counts.values.reduce(0, +)
        XCTAssertGreaterThan(Double(counts[.forest] ?? 0) / Double(land), 0.30, "\(counts)")
        XCTAssertGreaterThan(counts[.wetland] ?? 0, 0, "Mai Po and the border's ponds")
        XCTAssertGreaterThan(counts[.cropland] ?? 0, 0)
    }

    /// The pack lists the file, where it comes from and under what licence.
    func testThePackListsIt() throws {
        let pack = try XCTUnwrap(HongKongRailwaysTests.pack(.hongKong))
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: pack.file("pack", "json")) as? [String: Any])
        let files = try XCTUnwrap(manifest["files"] as? [String: Any])
        let entry = try XCTUnwrap(files["landcover.dat"] as? [String: Any])
        let size = try Data(contentsOf: pack.root.appendingPathComponent("landcover.dat")).count
        XCTAssertEqual(entry["bytes"] as? Int, size)
        XCTAssertLessThan(size, 300_000)
        let licences = try XCTUnwrap(manifest["licences"] as? [String: String])
        XCTAssertNotNil(licences["Planning Department land utilization"])
    }

    /// In Sai Kung's hills, the land cover's woods have trees and their
    /// ground the woods' pale green, the same every time.
    func testTheHillsHaveTreesAndGreenGround() throws {
        let ground = try Self.ground.get(), grid = try grid()
        var world = GameWorld.newOverseasGame(ground)
        try world.mapGround()
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let focus = frame.worldPosition(latitude: 22.400, longitude: 114.300)
        let tiles = try HongKongBaseMapTests.tiles()
        let plain = Map3DScene(world: world, focus: focus, baseMap: tiles, heights: ground.heights)
        let covered = Map3DScene(world: world, focus: focus, baseMap: tiles, heights: ground.heights, landCover: grid)
        let before = Self.trees(plain), after = Self.trees(covered)
        XCTAssertGreaterThan(after.count, before.count, "the land cover's woods have trees")
        XCTAssertEqual(Self.trees(Map3DScene(world: world, focus: focus, baseMap: tiles, heights: ground.heights, landCover: grid)).map(\.transform),
                       after.map(\.transform))
        let colours = Set(covered.chunks.flatMap { $0.mesh.vertices.map(\.color) })
        let plainColours = Set(plain.chunks.flatMap { $0.mesh.vertices.map(\.color) })
        XCTAssertTrue(colours.contains(Map3DPalette.ground(mixing: [.forest, .forest, .forest, .forest])))
        XCTAssertFalse(colours.subtracting(plainColours).isEmpty, "the ground is tinted")
    }

    private static func trees(_ scene: Map3DScene) -> [Map3DInstance] {
        let models = Set((Map3DSceneryProp.conifers.compactMap { Map3DScene.Builder.sceneryModels[$0] }) + [Map3DScene.Builder.propModels[.tree]].compactMap { $0 })
        return scene.chunks.flatMap(\.props).filter { models.contains($0.model) }
    }
}
