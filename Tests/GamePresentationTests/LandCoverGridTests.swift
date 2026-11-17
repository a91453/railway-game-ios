import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 811: the app's land cover file (ESA WorldCover, in the heights
/// file's form under `TWLC`) tints the 3D map's countryside and puts trees
/// in its forests.
@MainActor
final class LandCoverGridTests: XCTestCase {
    private static let grid: Result<LandCoverGrid, Error> = Result {
        try LandCoverGrid(data: RealWorldDataLoadTests.file("taiwan_landcover", "dat"))
    }

    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private static let tiles: Result<BaseMapTiles, Error> = Result {
        try BaseMapTiles(data: Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/BaseMap/taiwan.pmtiles"), options: .alwaysMapped))
    }

    private static let heights: Result<HeightGrid, Error> = Result {
        try HeightGrid(data: RealWorldDataLoadTests.file("taiwan_heights", "dat"))
    }

    /// Alishan's and the Pinglin hills' forests, the Changhua plain's
    /// fields and Taipei's built-up land; the open sea is not known.
    func testTheFileKnowsTaiwansGround() throws {
        let grid = try Self.grid.get()
        XCTAssertEqual(grid.cover(latitude: 23.53, longitude: 120.80), .forest, "Alishan")
        XCTAssertEqual(grid.cover(latitude: 24.94, longitude: 121.71), .forest, "Pinglin")
        XCTAssertEqual(grid.cover(latitude: 23.90, longitude: 120.45), .cropland, "the Changhua plain")
        XCTAssertEqual(grid.cover(latitude: 25.0478, longitude: 121.5170), .builtUp, "Taipei Main Station")
        XCTAssertNotNil(grid.cover(latitude: 24.44, longitude: 118.37), "Kinmen")
        XCTAssertNil(grid.cover(latitude: 24.0, longitude: 119.9), "the Taiwan Strait")
        XCTAssertNil(grid.cover(latitude: 10, longitude: 120), "off the grid")
    }

    func testAHeightsFileIsNotALandCoverFile() throws {
        XCTAssertThrowsError(try LandCoverGrid(data: RealWorldDataLoadTests.file("taiwan_heights", "dat")))
        XCTAssertThrowsError(try LandCoverGrid(data: RealWorldDataLoadTests.file("taiwan_coverage", "dat")))
    }

    /// Each cover's ground is the base map's cover of the same kind, so the
    /// two read as one, but the forest's, a paler green than the woods'
    /// (which would be too deep under the track); the built-up land, water
    /// and the unknown none.
    func testTheCoversGroundIsTheBaseMapsCover() {
        XCTAssertEqual(Map3DPalette.GroundKind(.forest)?.colour, Map3DPalette.forestFloor)
        XCTAssertEqual(Map3DPalette.GroundKind(.cropland)?.colour, Map3DPalette.cover(.farmland))
        XCTAssertEqual(Map3DPalette.GroundKind(.grassland)?.colour, Map3DPalette.cover(.grass))
        XCTAssertEqual(Map3DPalette.GroundKind(.shrubland)?.colour, Map3DPalette.cover(.grass))
        XCTAssertEqual(Map3DPalette.GroundKind(.wetland)?.colour, Map3DPalette.cover(.wetland))
        XCTAssertEqual(Map3DPalette.GroundKind(.bare)?.colour, Map3DPalette.bare)
        for cover in [LandCoverGrid.Cover.unknown, .builtUp, .water] {
            XCTAssertNil(Map3DPalette.GroundKind(cover), "\(cover)")
        }
        // The look leaves every mix where forest and plain ground meet as
        // it is (decision 370's kept colours).
        let edge = Map3DPalette.ground(mixing: [.forest, .forest, .plain, .field])
        XCTAssertTrue(Map3DLook.kept.contains(edge))
    }

    private static func world(_ latitude: Double, _ longitude: Double) throws -> GameWorld {
        var world = GameWorld.newGame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: latitude, longitudeDegrees: longitude)))
        try world.mapGround()
        return world
    }

    private static func trees(_ scene: Map3DScene) -> [Map3DInstance] {
        let models = Set((Map3DSceneryProp.conifers.compactMap { Map3DScene.Builder.sceneryModels[$0] }) + [Map3DScene.Builder.propModels[.tree]].compactMap { $0 })
        return scene.chunks.flatMap(\.props).filter { models.contains($0.model) }
    }

    /// On the hills of the East Rift Valley, a few hundred metres up, where
    /// OpenStreetMap maps little of the forest, the land cover's forest has
    /// trees and its ground the woods' green. The same every time, and at
    /// most four trees a 64 m cell.
    func testTheHillsForestsHaveTreesAndGreenGround() throws {
        let tiles = try Self.tiles.get(), heights = try Self.heights.get(), grid = try Self.grid.get()
        let world = try Self.world(23.60, 121.40)
        let plain = Map3DScene(world: world, baseMap: tiles, heights: heights)
        let covered = Map3DScene(world: world, baseMap: tiles, heights: heights, landCover: grid)
        let before = Self.trees(plain), after = Self.trees(covered)
        XCTAssertGreaterThan(after.count, before.count * 2, "the land cover's forests have trees")
        // Most of them broadleaf, low down.
        let broadleaf = try XCTUnwrap(Map3DScene.Builder.propModels[.tree])
        XCTAssertGreaterThan(after.filter { $0.model == broadleaf }.count, after.count / 2)
        // At most four on each 64 m cell: 256 on a 512 m chunk.
        let models = Set(after.map(\.model))
        XCTAssertLessThanOrEqual(covered.chunks.map { $0.props.filter { models.contains($0.model) }.count }.max() ?? 0, 256 + 64,
                                 "four a cell, and the street trees")
        XCTAssertEqual(Self.trees(Map3DScene(world: world, baseMap: tiles, heights: heights, landCover: grid)).map(\.transform),
                       after.map(\.transform))

        // The ground: the woods' green where no lot is, and a blend of it
        // at the forest's edges.
        let colours = Set(covered.chunks.flatMap { $0.mesh.vertices.map(\.color) })
        let plainColours = Set(plain.chunks.flatMap { $0.mesh.vertices.map(\.color) })
        let forest = Map3DPalette.GroundKind.forest.colour
        XCTAssertTrue(colours.contains(Map3DPalette.ground(mixing: [.forest, .forest, .forest, .forest])))
        XCTAssertTrue(colours.contains(forest))
        XCTAssertFalse(colours.subtracting(plainColours).isEmpty, "the ground is tinted")
    }

    /// The city stands on its lots: no tree of the land cover's stands on
    /// a lot's cell.
    func testNoForestTreeStandsOnTheCitysLots() throws {
        let tiles = try Self.tiles.get(), heights = try Self.heights.get(), grid = try Self.grid.get()
        let world = try Self.world(23.60, 121.40)
        let skyline = CitySkyline(world: world)
        let plain = Map3DScene(world: world, skyline: skyline, baseMap: tiles, heights: heights)
        let covered = Map3DScene(world: world, skyline: skyline, baseMap: tiles, heights: heights, landCover: grid)
        let added = Set(Self.trees(covered).map(\.transform)).subtracting(Self.trees(plain).map(\.transform))
        XCTAssertFalse(added.isEmpty)
        XCTAssertGreaterThan(skyline.lots.count, 100)
        let cell = Double(Land.cellLength)
        let lots = Set(skyline.lots.map { Map3DScene.ChunkKey(column: $0.column, row: $0.row) })
        for transform in added {
            let x = covered.originX + Double(transform[12]) * Map3DScene.Builder.metre
            let y = covered.originY + Double(transform[14]) * Map3DScene.Builder.metre
            let key = Map3DScene.ChunkKey(column: Int((x / cell).rounded(.down)), row: Int((y / cell).rounded(.down)))
            XCTAssertFalse(lots.contains(key), "a tree on lot \(key)")
        }
    }
}
