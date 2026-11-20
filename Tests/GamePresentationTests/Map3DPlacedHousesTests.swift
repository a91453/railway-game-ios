import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 897: the company's houses drawn from the residential kit,
/// close up only, a box round each tall model from farther, which of five
/// ways and which shed tin by the house's number.
final class Map3DPlacedHousesTests: XCTestCase {
    private func builder(_ world: GameWorld) -> Map3DScene.Builder {
        let (region, originX, originY) = Map3DScene.frame(world: world, focus: nil)
        return Map3DScene.Builder(originX: originX, originY: originY, region: region, world: world, heights: nil)
    }

    /// Each way stands inside the 14 m the house is drawn in, on the
    /// ground, with its boxes, within the kits' budget, and every way
    /// differs.
    func testEachWayIsInsideItsSquare() throws {
        let layouts = Map3DScene.Builder.placedHouseLayouts
        XCTAssertEqual(layouts.count, 5)
        let half = Float(Double(PlacedBuildingKind.house.side) / Map3DScene.Builder.metre) / 2 - 1
        for (index, layout) in layouts.enumerated() {
            let bounds = try XCTUnwrap(layout.mesh.bounds)
            for value in [bounds.min.x, bounds.min.z, -bounds.max.x, -bounds.max.z] {
                XCTAssertGreaterThanOrEqual(value, -half - 0.001, "way \(index) inside its square")
            }
            XCTAssertGreaterThanOrEqual(bounds.min.y, -0.01, "way \(index) stands on the ground")
            XCTAssertFalse(layout.boxes.isEmpty, "way \(index)")
            XCTAssertLessThanOrEqual(layout.mesh.triangleCount, 7_500, "way \(index)")
            XCTAssertFalse(layout.mesh.vertices.contains { $0.color == Map3DPalette.player }, "way \(index): no yellow box")
        }
        XCTAssertEqual(Set(layouts.map(\.mesh.triangleCount)).count, layouts.count, "each way its own")
    }

    /// The water tanks and sheds stand on their roofs: none of them
    /// floats above the roof or sinks into it (the kit's roof heights the
    /// layouts copy).
    func testRoofThingsStandOnTheRoofs() {
        let tank = Map3DResidentialKit.model(for: .waterTank)
        XCTAssertEqual(tank.minimum.z, 0, accuracy: 0.001)
        for (part, roof) in [(Map3DResidentialKit.Part.narrowTownhouse, Float(9.33)), (.arcadeTownhouse, 9.28),
                             (.roofTerraceHouse, 6.56), (.cornerHouse, 6.60), (.duplexHouse, 6.42)] {
            let model = Map3DResidentialKit.model(for: part)
            let flat = model.vertices.filter { $0.nz > 0.99 && abs($0.z - roof) < 0.001 }
            XCTAssertFalse(flat.isEmpty, "\(part) has a flat roof \(roof) m up")
        }
        let shed = Map3DScene.Builder.rooftopShed(length: 3, width: 4)
        XCTAssertEqual(shed.minimum.z, 0, accuracy: 0.001)
    }

    /// In the scene a house is its models close up and boxes from farther,
    /// not the box of decision 205; houses numbered one after another are
    /// drawn in different ways, their sheds' tin in the house's colour.
    func testTheSceneDrawsHousesFromTheKit() throws {
        var world = try makeWorld(width: 40_960, height: 40_960, balance: 1_000_000_000)
        var houses: [PlacedBuilding] = []
        for i in 0..<2 {
            houses.append(try world.placeBuilding(.house, at: PlanPoint(x: 8_192 + Int64(i) * 8_192, y: 8_192)))
        }
        var all = builder(world)
        all.addPlacedBuildings()
        XCTAssertGreaterThan(all.closeMeshes.values.reduce(0) { $0 + $1.triangleCount }, 2_000)
        let far = all.farMeshes.values.reduce(0) { $0 + $1.triangleCount }
        XCTAssertGreaterThan(far, 0)
        XCTAssertLessThan(far, 200)
        XCTAssertFalse(all.nearMeshes.values.contains { $0.vertices.contains { $0.color == Map3DPalette.player } }, "no yellow box close up")

        func close(_ house: PlacedBuilding) throws -> [Map3DVertex] {
            var one = builder(try makeWorld(width: 40_960, height: 40_960))
            let point = one.point(x: Double(house.centre.x), y: Double(house.centre.y), height: 0)
            XCTAssertTrue(one.addPlacedKitBuilding(house, base: point, side: 14))
            return one.closeMeshes.values.flatMap(\.vertices)
        }
        let a = try close(houses[0]), b = try close(houses[1])
        XCTAssertNotEqual(a.count, b.count, "two houses side by side differ")
        let count = Map3DScene.Builder.placedHouseLayouts.count, tins = Map3DScene.Builder.placedShedRoofs
        let shedTin = Map3DScene.Builder.shedTin
        func isShade(_ colour: UInt32, of base: UInt32) -> Bool {
            Map3DScene.Builder.placedRoof(colour, from: base, as: Map3DPalette.player) != colour
        }
        for (house, vertices) in zip(houses, [a, b]) {
            let layout = Map3DScene.Builder.placedHouseLayouts[house.id.rawValue % count]
            guard layout.mesh.vertices.contains(where: { isShade($0.color, of: shedTin) }) else { continue }
            let tin = tins[house.id.rawValue / count % tins.count]
            XCTAssertTrue(vertices.contains { isShade($0.color, of: tin) }, "the house's own tin")
            if tin != shedTin { XCTAssertFalse(vertices.contains { isShade($0.color, of: shedTin) }, "no tin left in the shed's first colour") }
        }
    }

    /// The shed's tin takes another colour in its own shade, and nothing
    /// else in the kit's houses is a shade of the tin.
    func testOnlyTheTinTakesTheColour() {
        let tin = Map3DScene.Builder.shedTin
        // The kit's houses and roof things have none of it: only the sheds
        // and awnings change colour.
        for part in Map3DResidentialKit.Part.allCases {
            let model = Map3DResidentialKit.model(for: part)
            XCTAssertFalse(model.vertices.contains { Map3DScene.Builder.placedRoof($0.color, from: tin, as: Map3DPalette.crown) != $0.color }, part.id)
        }
        let awning = Map3DScene.Builder.streetAwning(width: 5)
        XCTAssertTrue(awning.vertices.allSatisfy { Map3DScene.Builder.placedRoof($0.color, from: tin, as: Map3DPalette.crown) != $0.color })
        let shed = Map3DScene.Builder.rooftopShed(length: 3, width: 4)
        let walls = shed.vertices.filter { Map3DScene.Builder.placedRoof($0.color, from: tin, as: Map3DPalette.crown) == $0.color }
        XCTAssertFalse(walls.isEmpty, "the shed's walls keep their grey")
        XCTAssertEqual(Map3DScene.Builder.placedRoof(Map3DColor.shaded(tin, 0.8), from: tin, as: Map3DPalette.crown),
                       Map3DColor.shaded(Map3DPalette.crown, 0.8))
    }
}
