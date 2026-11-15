import XCTest
@testable import GamePresentation

/// The winter event's trees, string of lights and livery colours
/// (``Map3DWinterDecor``).
final class Map3DWinterDecorTests: XCTestCase {
    private func model(_ decor: Map3DWinterDecor) throws -> Map3DModelPack.Model {
        try XCTUnwrap(decor.model, decor.rawValue)
    }

    func testEveryModelDecodesWithinItsBudget() throws {
        let budget: [Map3DWinterDecor: Int] = [
            .treeMedium: 700, .treeMediumFar: 200, .treeLarge: 1_200, .treeLargeFar: 300, .lightString: 160,
        ]
        for decor in Map3DWinterDecor.allCases {
            let m = try model(decor)
            XCTAssertGreaterThan(m.triangleCount, 0, decor.rawValue)
            XCTAssertLessThanOrEqual(m.triangleCount, try XCTUnwrap(budget[decor]), decor.rawValue)
            XCTAssertEqual(m.name, "winter-" + decor.rawValue)
        }
    }

    func testTheTreesStandOnTheGroundAtTheirHeights() throws {
        for (decor, height) in [(Map3DWinterDecor.treeMedium, Float(6)), (.treeMediumFar, 6), (.treeLarge, 18), (.treeLargeFar, 18)] {
            let m = try model(decor)
            XCTAssertEqual(m.minimum.z, 0, accuracy: 0.01, decor.rawValue)
            XCTAssertEqual(m.maximum.z, height, accuracy: 0.05, decor.rawValue)
            // Round its middle.
            XCTAssertEqual(m.minimum.x + m.maximum.x, 0, accuracy: 0.1, decor.rawValue)
            XCTAssertEqual(m.minimum.y + m.maximum.y, 0, accuracy: 0.1, decor.rawValue)
        }
        // The far models fill the near ones' box.
        for (near, far) in [(Map3DWinterDecor.treeMedium, Map3DWinterDecor.treeMediumFar), (.treeLarge, .treeLargeFar)] {
            let a = try model(near), b = try model(far)
            XCTAssertEqual(a.maximum.z, b.maximum.z, accuracy: 0.01)
            XCTAssertEqual(a.maximum.x - a.minimum.x, b.maximum.x - b.minimum.x, accuracy: 0.05)
        }
    }

    func testTheStringHangsFromItsEnds() throws {
        let m = try model(.lightString)
        XCTAssertEqual(m.minimum.x, -2, accuracy: 0.01)
        XCTAssertEqual(m.maximum.x, 2, accuracy: 0.01)
        XCTAssertEqual(m.maximum.z, 0, accuracy: 0.02)
        XCTAssertLessThan(m.minimum.z, -0.2, "it sags")
    }

    func testOnlyTheBulbsGlowAndEachModelHasFewEnoughGlows() throws {
        let lit = Set(Map3DWinterDecor.Material.allCases.filter(\.isBulb).map { Map3DWinterDecor.palette[$0.rawValue] })
        let unlit = Set(Map3DWinterDecor.Material.allCases.filter { !$0.isBulb }.map { Map3DWinterDecor.palette[$0.rawValue] })
        XCTAssertTrue(lit.isDisjoint(with: unlit), "a bulb's colour is its own")
        for decor in Map3DWinterDecor.allCases {
            let m = try model(decor)
            for v in m.vertices {
                XCTAssertEqual(v.layer == Map3DVertex.glowing, lit.contains(v.color), decor.rawValue)
            }
            let spots = Map3DGlow.spots(of: m)
            XCTAssertFalse(spots.isEmpty, decor.rawValue)
            XCTAssertLessThanOrEqual(spots.count, Map3DGlow.mostAModel, decor.rawValue)
        }
        // The large tree's bands are beads, not one lit panel: the most glows a model has.
        XCTAssertEqual(Map3DGlow.spots(of: try model(.treeLarge)).count, Map3DGlow.mostAModel)
        // The string's eight bulbs glow apart, in four colours.
        let string = Map3DGlow.spots(of: try model(.lightString))
        XCTAssertEqual(string.count, 8)
        XCTAssertEqual(Set(string.map { [$0.red, $0.green, $0.blue] }).count, 4)
    }

    func testTheLiveryIsRedWhiteAndGoldFromTheTreesColours() {
        let livery = Map3DWinterDecor.christmasLivery
        XCTAssertEqual(livery.body, Map3DColor.rgb(0xC1272F))
        XCTAssertEqual(livery.band, Map3DColor.rgb(0xF2F3EE))
        XCTAssertEqual(livery.line, Map3DColor.rgb(0xF2C230))
        // Apart from the Puyuma's white body and red band.
        XCTAssertNotEqual(livery.body, Map3DColor.rgb(UInt32(TrainLivery.puyuma.body ?? 0)))
    }

    func testEveryColourIsOneTheGameAlreadyHas() {
        // No new palette colour (the studio's are matched to the nearest).
        let colours = Map3DWinterDecor.Material.allCases.map(\.colour)
        XCTAssertEqual(Set(colours).count, colours.count, "each material its own colour")
        XCTAssertEqual(Map3DWinterDecor.Material.trunk.colour, Map3DPalette.trunk)
        XCTAssertEqual(Map3DWinterDecor.Material.bulbGold.colour, Map3DPalette.player)
    }
}
