import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 398: the company's hotels, department stores, amusement park,
/// wharves and marinas drawn from the estate and coastal kits (and since
/// decision 361's sequel its schools, hospitals and night markets from the
/// civic, park and commercial kits), close up
/// only; from farther a box round each tall model.
final class Map3DPlacedBuildingKitsTests: XCTestCase {
    private static let kinds: [PlacedBuildingKind] = [.hotel, .departmentStore, .amusementPark, .wharf, .marina, .school, .hospital, .nightMarket]

    private func builder(_ world: GameWorld) -> Map3DScene.Builder {
        let (region, originX, originY) = Map3DScene.frame(world: world, focus: nil)
        return Map3DScene.Builder(originX: originX, originY: originY, region: region, world: world, heights: nil)
    }

    private func triangles(_ meshes: [Map3DScene.ChunkKey: Map3DMesh]) -> Int {
        meshes.values.reduce(0) { $0 + $1.triangleCount }
    }

    /// Each look of each kind has its layout, inside its square, named for
    /// the player, with a box to stand for it from farther, and no more
    /// triangles close up than the large temple of decision 361 and a
    /// half.
    func testEachLookHasALayoutInsideItsSquare() throws {
        for kind in Self.kinds {
            let layouts = try XCTUnwrap(Map3DScene.Builder.placedKitLayouts[kind])
            XCTAssertEqual(layouts.count, kind.looks, "\(kind)")
            for (look, layout) in layouts.enumerated() {
                if kind.looks > 1 { XCTAssertNotNil(kind.lookTitle(look, in: .traditionalChinese), "\(kind) \(look)") }
                let bounds = try XCTUnwrap(layout.mesh.bounds)
                let half = Float(Double(kind.side) / Map3DScene.Builder.metre) / 2
                for value in [bounds.min.x, bounds.min.z, -bounds.max.x, -bounds.max.z] {
                    XCTAssertGreaterThanOrEqual(value, -half, "\(kind) \(look) inside its square")
                }
                XCTAssertGreaterThanOrEqual(bounds.min.y, -0.2, "\(kind) \(look) stands on the ground")
                XCTAssertFalse(layout.boxes.isEmpty, "\(kind) \(look)")
                XCTAssertLessThanOrEqual(layout.mesh.triangleCount, 7_500, "\(kind) \(look)")
            }
        }
        XCTAssertEqual(Set(Map3DScene.Builder.placedKitLayouts.keys), Set(Self.kinds))
    }

    /// The marina's boats and floating piers sit in its water by their
    /// waterline (the coastal-kit skill), as the kit's fishing harbour
    /// does: the dinghy's origin 2 cm under the quay's foot, the pier's
    /// 8 cm over it.
    func testTheMarinasBoatsFloatAtTheirWaterline() throws {
        let marina = try XCTUnwrap(Map3DScene.Builder.placedKitLayouts[.marina]?.first)
        let harbour = Map3DCoastalKit.placements(for: .fishingHarbor)
        XCTAssertEqual(harbour.first { $0.part == .motorDinghy }?.position.z ?? 0, -0.02, accuracy: 0.001)
        XCTAssertEqual(harbour.first { $0.part == .floatingPontoon }?.position.z ?? 0, 0.08, accuracy: 0.001)
        let water = try XCTUnwrap(marina.mesh.vertices.filter { $0.color == Map3DPalette.water }.map(\.y).max())
        XCTAssertEqual(water, 0.3, accuracy: 0.001)
    }

    /// The estate kit's cream roofs take one of four colours by the
    /// building's number, the walls and the company's yellow staying.
    func testTheirRoofsDifferByBuilding() throws {
        var world = try makeWorld(width: 40_960, height: 40_960, balance: 1_000_000_000)
        let first = try world.placeBuilding(.hotel, at: PlanPoint(x: 8_192, y: 8_192))
        let second = try world.placeBuilding(.hotel, at: PlanPoint(x: 20_480, y: 8_192))
        let layout = try XCTUnwrap(Map3DScene.Builder.placedKitLayouts[.hotel]?.first)
        XCTAssertTrue(layout.mesh.vertices.contains { $0.color == Map3DPalette.playerRoof }, "the kit's roofs are its cream")
        func roofs(_ building: PlacedBuilding) throws -> Set<UInt32> {
            // Only this building, on its own.
            var builder = builder(try makeWorld(width: 40_960, height: 40_960))
            let point = builder.point(x: Double(building.centre.x), y: Double(building.centre.y), height: 0)
            XCTAssertTrue(builder.addPlacedKitBuilding(building, base: point, side: 30))
            let colours = Set(builder.closeMeshes.values.flatMap { $0.vertices.map(\.color) })
            XCTAssertFalse(colours.contains { Map3DScene.Builder.placedRoof($0, as: Map3DPalette.player) != $0 }, "no cream left, sloped or flat")
            XCTAssertTrue(colours.contains(Map3DPalette.player), "the company's yellow stays")
            return colours.intersection(Map3DScene.Builder.placedRoofs)
        }
        let a = try roofs(first), b = try roofs(second)
        XCTAssertEqual(a.count, 1)
        XCTAssertEqual(b.count, 1)
        XCTAssertNotEqual(a, b)
    }

    /// A shade of the cream takes the same shade of the new colour; the
    /// company's yellow and the white walls stay.
    func testAShadedRoofKeepsItsShade() {
        let blue = Map3DPalette.tinRoofs[0]
        XCTAssertEqual(Map3DScene.Builder.placedRoof(Map3DPalette.playerRoof, as: blue), blue)
        XCTAssertEqual(Map3DScene.Builder.placedRoof(Map3DColor.shaded(Map3DPalette.playerRoof, 0.8), as: blue), Map3DColor.shaded(blue, 0.8))
        for other in [Map3DPalette.player, Map3DPalette.tileWhite, Map3DPalette.concrete, Map3DPalette.water] {
            XCTAssertEqual(Map3DScene.Builder.placedRoof(other, as: blue), other)
        }
    }

    /// A wharf faces the sea: its water half out over the water.
    func testAWharfFacesTheSea() throws {
        var world = try makeWorld(width: 40_960, height: 40_960, balance: 1_000_000_000)
        // The sea north of y 8,192 (rows 0 and 1); a wharf on its edge.
        try world.setWater((0...1).flatMap { row in (0...9).map { CellPosition(row: row, column: $0) } })
        let wharf = try world.placeBuilding(.wharf, at: PlanPoint(x: 20_480, y: 8_192))
        let builder = builder(world)
        XCTAssertEqual(builder.seaward(of: wharf), Map3DPoint(0, 0, -1))
    }

    /// Close up the models, from farther only boxes: the amusement park's
    /// six models some 6,000 triangles, their six boxes 60.
    func testCloseUpOnly() throws {
        var world = try makeWorld(width: 40_960, height: 40_960, balance: 1_000_000_000)
        try world.placeBuilding(.amusementPark, at: PlanPoint(x: 20_480, y: 20_480))
        var builder = builder(world)
        builder.addPlacedBuildings()
        let close = triangles(builder.closeMeshes), far = triangles(builder.farMeshes), standIn = triangles(builder.standInMeshes)
        XCTAssertGreaterThan(close, 5_000)
        XCTAssertLessThan(far, 200)
        XCTAssertEqual(standIn, far)
        // The boxes are not in the full mesh drawn under the models.
        XCTAssertEqual(triangles(builder.nearMeshes), 0)
    }

    /// Close up a hotel or department store is its models, not the box
    /// round them: the box is drawn in full only where its model is not.
    func testTheBoxesGiveWayToTheModelsCloseUp() throws {
        var world = try makeWorld(width: 40_960, height: 40_960, balance: 1_000_000_000)
        try world.placeBuilding(.hotel, at: PlanPoint(x: 12_288, y: 20_480))
        try world.placeBuilding(.departmentStore, at: PlanPoint(x: 28_672, y: 20_480))
        let scene = Map3DScene(world: world, snapshot: world.railwaySnapshot())
        for chunk in scene.chunks where !chunk.standIn.isEmpty {
            // The models close up; their boxes apart, the same as from afar.
            XCTAssertFalse(chunk.close.isEmpty)
            XCTAssertEqual(chunk.standIn.triangleCount, chunk.far.triangleCount)
        }
        XCTAssertEqual(scene.chunks.filter { !$0.standIn.isEmpty }.count, 2)
    }
}
