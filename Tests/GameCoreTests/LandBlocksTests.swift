import Foundation
@testable import GameCore
import XCTest

/// Land read in as it is needed (decision 88): blocks of 16 × 16 cells,
/// which blocks lie within a reach of a point, reading them in, and their
/// save form.
final class LandBlocksTests: XCTestCase {
    private let bounds = try! WorldBounds(width: 1 << 25, height: 3 << 23)

    private func world(buildings: Bool = true) -> GameWorld {
        var world = GameWorld(bounds: bounds, economy: GameEconomy(balance: 100_000_000, costs: testCosts))
        world.setEconomyMode(.management)
        world.setLandDemand(true)
        world.setCityBuildings(buildings)
        world.setLandOnDemand()
        return world
    }

    private func cell(_ row: Int, _ column: Int, residents: Int64 = 100, jobs: Int64 = 0, use: LandUse = .residential) -> LandCell {
        LandCell(row: row, column: column, use: use, residents: residents, jobs: jobs)
    }

    // MARK: - Blocks

    func testABlockIsSixteenCellsOrAKilometreASide() throws {
        XCTAssertEqual(Land.blockCells, 16)
        XCTAssertEqual(Land.blockLength, 65_536)
        XCTAssertEqual(Land.blockLength / WorldCoordinate.unitsPerMetre, 1_024)
        XCTAssertEqual(LandBlock(cellRow: 15, column: 16), LandBlock(row: 0, column: 1))
        XCTAssertEqual(Land.blockRows(in: bounds), 384)
        XCTAssertEqual(Land.blockColumns(in: bounds), 512)
        let ragged = try WorldBounds(width: 65_537, height: 65_536)
        XCTAssertEqual(Land.blockColumns(in: ragged), 2, "the last block reaches past the edge")
        XCTAssertEqual(Land.blockRows(in: ragged), 1)
    }

    /// A block is within reach when any part of it is closer than the
    /// radius, compared squared, exactly; blocks outside the world are left
    /// out.
    func testTheBlocksWithinAReachAreThoseAnyPartOfWhichIsCloser() throws {
        let length = Land.blockLength
        let middle = PlanPoint(x: 100 * length + length / 2, y: 50 * length + length / 2)
        XCTAssertEqual(Land.blocks(within: length / 2, of: middle, in: bounds), [LandBlock(row: 50, column: 100)])
        // The middle unit is 32,768 units from the next block east and
        // south, 32,769 from the next west and north: two units further
        // reaches the four blocks beside it, not the corners.
        XCTAssertEqual(Land.blocks(within: length / 2 + 1, of: middle, in: bounds).count, 3)
        let plus = Land.blocks(within: length / 2 + 2, of: middle, in: bounds)
        XCTAssertEqual(plus, [
            LandBlock(row: 49, column: 100), LandBlock(row: 50, column: 99), LandBlock(row: 50, column: 100),
            LandBlock(row: 50, column: 101), LandBlock(row: 51, column: 100),
        ])
        // Worked out block by block for a reach of 2 km.
        let radius: Int64 = 128_000
        let point = PlanPoint(x: 20_000_000, y: 18_000_000)
        var expected: [LandBlock] = []
        for row in 0..<Land.blockRows(in: bounds) {
            for column in 0..<Land.blockColumns(in: bounds) {
                let nearestX = min(max(point.x, Int64(column) * length), Int64(column + 1) * length - 1)
                let nearestY = min(max(point.y, Int64(row) * length), Int64(row + 1) * length - 1)
                let dx = nearestX - point.x, dy = nearestY - point.y
                if dx * dx + dy * dy < radius * radius {
                    expected.append(LandBlock(row: row, column: column))
                }
            }
        }
        XCTAssertEqual(Land.blocks(within: radius, of: point, in: bounds), expected)
        XCTAssertEqual(expected.count, 22)
        // At the world's corner only the blocks inside.
        XCTAssertEqual(Land.blocks(within: 10, of: PlanPoint(x: 0, y: 0), in: bounds), [LandBlock(row: 0, column: 0)])
        XCTAssertEqual(Land.blocks(within: 0, of: point, in: bounds), [])
    }

    // MARK: - Reading blocks in

    func testOnDemandLandStartsEmptyAndWholeLandSetsItBack() throws {
        var world = GameWorld(bounds: .standard, economy: GameEconomy(balance: 0, costs: testCosts))
        world.setCityBuildings(true)
        world.foundTowns(seed: 1)
        XCTAssertNil(world.landBlocks, "land is whole")
        world.setLandOnDemand()
        XCTAssertEqual(world.landBlocks, [])
        XCTAssertTrue(world.land.isEmpty)
        XCTAssertTrue(world.buildings.isEmpty)
        world.foundTowns(seed: 1)
        XCTAssertNil(world.landBlocks)
        world.setLandOnDemand()
        try world.setLand([cell(0, 0)])
        XCTAssertNil(world.landBlocks)
    }

    /// Reading blocks in adds their cells with their buildings, numbered
    /// after the others, keeps a cell already there, and gives a station
    /// its ridership from them at once.
    func testReadingBlocksInAddsTheirCellsAndBuildings() throws {
        var world = world()
        let point = PlanPoint(x: 20_000_000, y: 18_000_000)
        let station = try world.buildStation(named: "Far", at: point).id
        XCTAssertNil(world.stationDemand(of: station), "no one lives round it yet")
        let row = Int(point.y / Land.cellLength), column = Int(point.x / Land.cellLength)
        let blocks = Land.blocks(within: 128_000, of: point, in: bounds)
        try world.expandLand(blocks, cells: [cell(row, column + 1, residents: 50), cell(row, column, residents: 200)])
        XCTAssertEqual(world.landBlocks, blocks)
        XCTAssertEqual(world.land.cells.map(\.residents), [200, 50], "by row and then column")
        XCTAssertEqual(world.buildings.all.map(\.id.rawValue), [1, 2])
        XCTAssertEqual(world.buildings.building(row: row, column: column)?.id.rawValue, 1)
        XCTAssertEqual(world.landCatchment(of: station)?.residents, 250)
        XCTAssertNotNil(world.stationDemand(of: station), "its ridership comes from the land read")

        // More blocks: a cell the land already has keeps what it has.
        let next = [LandBlock(row: 0, column: 0)]
        var grown = world
        grown.land.insert(cell(3, 3, residents: 7))
        grown.buildings.append(Building.fitting(cell(3, 3, residents: 7), id: BuildingID(rawValue: 3)))
        try grown.expandLand(next, cells: [cell(3, 3, residents: 900), cell(15, 15, residents: 9)])
        XCTAssertEqual(grown.land.cell(row: 3, column: 3)?.residents, 7)
        XCTAssertEqual(grown.land.cell(row: 15, column: 15)?.residents, 9)
        XCTAssertEqual(grown.buildings.building(row: 15, column: 15)?.id.rawValue, 4)
        XCTAssertEqual(grown.landBlocks, (blocks + next).sorted())
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(grown)), grown, "a world GameCore loads")

        // With the buildings off, the cells only.
        var bare = self.world(buildings: false)
        try bare.expandLand(next, cells: [cell(1, 1)])
        XCTAssertEqual(bare.land.cells.count, 1)
        XCTAssertTrue(bare.buildings.isEmpty)
    }

    func testBadBlocksAndCellsAreRefusedAndChangeNothing() throws {
        var world = world()
        try world.expandLand([LandBlock(row: 2, column: 2)], cells: [cell(40, 40)])
        let before = world
        let refused: [([LandBlock], [LandCell], String)] = [
            ([LandBlock(row: 384, column: 0)], [], "a block below the world"),
            ([LandBlock(row: 0, column: 512)], [], "a block east of it"),
            ([LandBlock(row: -1, column: 0)], [], "a block north of it"),
            ([LandBlock(row: 1, column: 1), LandBlock(row: 1, column: 1)], [], "a block twice"),
            ([LandBlock(row: 2, column: 2)], [], "a block read already"),
            ([LandBlock(row: 1, column: 1)], [cell(0, 0)], "a cell outside the blocks"),
            ([LandBlock(row: 1, column: 1)], [cell(20, 20), cell(20, 20)], "a cell twice"),
            ([LandBlock(row: 1, column: 1)], [cell(20, 20, residents: 0)], "no one there"),
            ([LandBlock(row: 1, column: 1)], [cell(20, 20, residents: -1)], "a negative count"),
            ([LandBlock(row: 1, column: 1)], [cell(20, 20, residents: Land.maximumPerCell + 1)], "too many"),
        ]
        for (blocks, cells, reason) in refused {
            XCTAssertThrowsGameError(try world.expandLand(blocks, cells: cells), .invalidLand)
            XCTAssertEqual(world, before, reason)
        }
        var whole = GameWorld(bounds: .standard, economy: GameEconomy(balance: 0, costs: testCosts))
        XCTAssertThrowsGameError(try whole.expandLand([LandBlock(row: 0, column: 0)], cells: []), .invalidLand)
    }

    // MARK: - Saving

    func testTheBlocksSaveAsRunsAndBadOnesAreRefused() throws {
        var world = world()
        let blocks = [LandBlock(row: 3, column: 4), LandBlock(row: 3, column: 5), LandBlock(row: 3, column: 7), LandBlock(row: 4, column: 0)]
        try world.expandLand(blocks.reversed(), cells: [cell(48, 64)])
        let data = try JSONEncoder().encode(world)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let runs = try XCTUnwrap(object["landBlocks"] as? [[String: Int]])
        XCTAssertEqual(runs, [["row": 3, "column": 4, "count": 2], ["row": 3, "column": 7, "count": 1], ["row": 4, "column": 0, "count": 1]])
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: data), world)

        var empty = self.world()
        empty.setEconomyMode(.free)
        let none = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(empty)) as? [String: Any])
        XCTAssertEqual((none["landBlocks"] as? [Any])?.count, 0, "no block read yet is still land read as needed")
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(empty)).landBlocks, [])
        let whole = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(GameWorld(bounds: .standard, economy: GameEconomy(balance: 0, costs: testCosts)))) as? [String: Any])
        XCTAssertNil(whole["landBlocks"], "whole land writes none")

        func load(_ runs: [[String: Int]]) -> GameWorld? {
            var changed = object
            changed["landBlocks"] = runs
            return try? JSONDecoder().decode(GameWorld.self, from: JSONSerialization.data(withJSONObject: changed))
        }
        XCTAssertNotNil(load([["row": 0, "column": 0, "count": 512]]), "a whole row")
        XCTAssertNil(load([["row": 0, "column": 0, "count": 0]]), "an empty run")
        XCTAssertNil(load([["row": 0, "column": 0, "count": 513]]), "more than a row holds")
        XCTAssertNil(load([["row": 0, "column": 511, "count": 2]]), "past the world's east edge")
        XCTAssertNil(load([["row": 384, "column": 0, "count": 1]]), "below the world")
        XCTAssertNil(load([["row": 1, "column": 0, "count": 1], ["row": 0, "column": 0, "count": 1]]), "out of order")
        XCTAssertNil(load([["row": 0, "column": 0, "count": 2], ["row": 0, "column": 1, "count": 1]]), "a block twice")
    }
}
