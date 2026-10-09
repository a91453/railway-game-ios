import Foundation
@testable import GameCore
import XCTest

/// Terrain (ARCHITECTURE decision 105): water, a layer of its own under the
/// land, where the city does not spread and the player neither places a
/// building nor zones; track still crosses it. Every number below is worked
/// out by hand.
final class TerrainTests: XCTestCase {
    /// 32 × 24 cells.
    private static let small = try! WorldBounds(width: 131_072, height: 98_304)
    /// 64 × 64 cells, 4 × 4 blocks of land.
    private static let blocks = try! WorldBounds(width: 262_144, height: 262_144)
    /// Station S0 stands at the middle of cell (5, 5), where 1,000 people
    /// live.
    private static let stationPoint = PlanPoint(x: 22_528, y: 22_528)

    private func cells(_ rows: ClosedRange<Int>, _ columns: ClosedRange<Int>) -> [CellPosition] {
        rows.flatMap { row in columns.map { CellPosition(row: row, column: $0) } }
    }

    /// A managed world with the sea north of row 5 (rows 0 to 4) and a river
    /// down column 10 below it; one home cell at (5, 5), and town growth
    /// with the station S0 there, measured at 800.
    private func world() throws -> GameWorld {
        var world = GameWorld(bounds: Self.small, economy: GameEconomy(balance: 1_000_000_000, costs: testCosts), clock: GameClock(speed: .normal))
        try world.setWater(cells(0...4, 0...31) + cells(5...23, 10...10))
        try world.setLand([LandCell(row: 5, column: 5, use: .residential, residents: 1_000, jobs: 0)])
        world.setEconomyMode(.management)
        world.setLandDemand(true)
        world.setTownGrowth(true)
        try world.buildStation(named: "S0", at: Self.stationPoint)
        world.growLand(reached: [:])
        world.townGrowth!.places[0].lastService = 800
        world.townGrowth!.places[0].lastReached = 2
        return world
    }

    // MARK: - The layer

    func testWaterIsRunsAlongTheRowsWhateverTheOrder() {
        let cells = [CellPosition(row: 2, column: 5), CellPosition(row: 1, column: 3), CellPosition(row: 2, column: 4), CellPosition(row: 1, column: 1)]
        let terrain = Terrain(water: cells)
        XCTAssertEqual(terrain.water, [
            WaterRun(row: 1, column: 1, count: 1), WaterRun(row: 1, column: 3, count: 1), WaterRun(row: 2, column: 4, count: 2),
        ])
        XCTAssertEqual(Terrain(water: cells.reversed()), terrain)
        XCTAssertEqual(terrain.waterCellCount, 4)
        XCTAssertTrue(terrain.isWater(row: 2, column: 5))
        XCTAssertFalse(terrain.isWater(row: 2, column: 6))
        XCTAssertFalse(terrain.isWater(row: 1, column: 2))
        XCTAssertFalse(terrain.isWater(row: 0, column: 1))
        // Cells added beside or between runs join them.
        var added = terrain
        added.add([CellPosition(row: 1, column: 2), CellPosition(row: 2, column: 3)])
        XCTAssertEqual(added.water, [WaterRun(row: 1, column: 1, count: 3), WaterRun(row: 2, column: 3, count: 3)])
        XCTAssertEqual(Terrain.union(added.water, terrain.water), added.water, "a cell already water is water once")
    }

    func testSettingWaterReplacesIt() throws {
        var world = GameWorld(bounds: Self.small, economy: GameEconomy(balance: 0, costs: testCosts))
        XCTAssertTrue(world.terrain.isEmpty)
        try world.setWater(cells(0...1, 0...31))
        XCTAssertEqual(world.terrain.water, [WaterRun(row: 0, column: 0, count: 32), WaterRun(row: 1, column: 0, count: 32)])
        XCTAssertTrue(world.isWater(row: 1, column: 31))
        try world.setWater([CellPosition(row: 3, column: 3)])
        XCTAssertEqual(world.terrain.waterCellCount, 1)
        try world.setWater([])
        XCTAssertTrue(world.terrain.isEmpty)
    }

    func testBadWaterIsRefused() throws {
        var world = try world()
        let before = world
        for bad in [
            [CellPosition(row: 24, column: 0)], [CellPosition(row: 0, column: 32)], [CellPosition(row: -1, column: 0)],
            [CellPosition(row: 6, column: 6), CellPosition(row: 6, column: 6)],
            // Land is there.
            [CellPosition(row: 5, column: 5)],
        ] {
            XCTAssertThrowsError(try world.setWater(bad)) { XCTAssertEqual($0 as? GameError, .invalidTerrain) }
        }
        XCTAssertEqual(world, before)
        // Land read as it is needed reads its water with its blocks.
        var onDemand = GameWorld(bounds: Self.blocks, economy: GameEconomy(balance: 0, costs: testCosts))
        onDemand.setLandOnDemand()
        XCTAssertThrowsError(try onDemand.setWater([CellPosition(row: 0, column: 0)])) { XCTAssertEqual($0 as? GameError, .invalidTerrain) }
    }

    func testLandIsNotSetOnWaterAndTownsLeaveItOut() throws {
        var world = try world()
        XCTAssertThrowsError(try world.setLand([LandCell(row: 4, column: 5, use: .residential, residents: 1, jobs: 0)])) {
            XCTAssertEqual($0 as? GameError, .invalidLand)
        }
        // A blank map's first town lies round the middle, (12, 16): its
        // cells in rows 4 and above, and in column 10, are left out.
        var blank = GameWorld(bounds: Self.small, economy: GameEconomy(balance: 0, costs: testCosts))
        blank.foundTowns(seed: 1)
        let dry = blank.land.cells.filter { $0.row > 4 && $0.column != 10 }
        XCTAssertGreaterThan(dry.count, 0)
        XCTAssertLessThan(dry.count, blank.land.cells.count)
        var wet = GameWorld(bounds: Self.small, economy: GameEconomy(balance: 0, costs: testCosts))
        try wet.setWater(cells(0...4, 0...31) + cells(5...23, 10...10))
        wet.foundTowns(seed: 1)
        XCTAssertEqual(wet.land.cells, dry)
    }

    // MARK: - Rules

    func testTheTownDoesNotSpreadOntoWater() throws {
        var world = try world()
        world.spread(towards: world.stations[0])
        // (4, 5), the first of the four cells beside (5, 5), is the sea: by
        // row and then column, (5, 4).
        XCTAssertNil(world.land.cell(row: 4, column: 5))
        XCTAssertEqual(world.land.cell(row: 5, column: 4), LandCell(row: 5, column: 4, use: .residential, residents: 4, jobs: 0))
        for _ in 0..<40 {
            world.spread(towards: world.stations[0])
        }
        XCTAssertEqual(world.land.cells.count, 42)
        XCTAssertFalse(world.land.cells.contains { world.isWater(row: $0.row, column: $0.column) })
        XCTAssertNil(world.terrainProblem())
    }

    func testAZoneOnWaterIsNotBuiltOn() throws {
        var world = try world()
        // Column 10 is the river; 11 is land.
        XCTAssertEqual(try world.setZone(.commercial, rows: 8...8, columns: 10...11), 1)
        XCTAssertNil(world.zones.zone(row: 8, column: 10))
        XCTAssertEqual(world.zones.zone(row: 8, column: 11), .commercial)
        world.spread(towards: world.stations[0])
        XCTAssertEqual(world.land.cell(row: 8, column: 11)?.use, .commercial)
        XCTAssertNil(world.land.cell(row: 8, column: 10))
    }

    func testWaterIsNotZoned() throws {
        var world = try world()
        let before = world
        XCTAssertThrowsError(try world.setZone(.residential, rows: 2...4, columns: 3...5)) {
            XCTAssertEqual($0 as? GameError, .onWater(row: 2, column: 3))
        }
        XCTAssertThrowsError(try world.setZone(.reserved, rows: 9...9, columns: 10...10)) {
            XCTAssertEqual($0 as? GameError, .onWater(row: 9, column: 10))
        }
        XCTAssertEqual(world, before)
        // Clearing is allowed: there is nothing to clear.
        XCTAssertEqual(try world.setZone(nil, rows: 2...4, columns: 3...5), 0)
        // A rectangle from the sea onto the land zones the land: rows 3 to
        // 6 by columns 0 to 1, rows 5 and 6 dry.
        XCTAssertEqual(try world.setZone(.residential, rows: 3...6, columns: 0...1), 4)
        XCTAssertEqual(world.zones.cells.map(\.position), cells(5...6, 0...1))
    }

    func testABuildingCannotStandOnWater() throws {
        var world = try world()
        let before = world
        // A house is 1,024 (16 m) a side. Centred at (40,960, 22,528), it
        // spans x 40,448 to 41,472: column 9 (to 40,960) and 10, the river.
        XCTAssertThrowsError(try world.placeBuilding(.house, at: PlanPoint(x: 40_960, y: 22_528))) {
            XCTAssertEqual($0 as? GameError, .onWater(row: 5, column: 10))
        }
        // Centred on (5, 3)'s north edge, y 20,480: half in row 4, the sea.
        XCTAssertThrowsError(try world.placeBuilding(.house, at: PlanPoint(x: 14_336, y: 20_480))) {
            XCTAssertEqual($0 as? GameError, .onWater(row: 4, column: 3))
        }
        XCTAssertEqual(world, before)
        // Touching the river's edge (x 40,960) from the west is dry.
        let house = try world.placeBuilding(.house, at: PlanPoint(x: 40_448, y: 26_624))
        XCTAssertEqual(house.maxX, 40_960)
    }

    /// A wharf and a marina stand on the shore: part of the square over
    /// water, part on land; wholly on either is refused.
    func testAWharfOrAMarinaStandsOnTheShore() throws {
        var world = try world()
        XCTAssertEqual(PlacedBuildingKind.wharf.capacity, BuildingCapacity(residents: 6, jobs: 27))
        XCTAssertEqual(PlacedBuildingKind.marina.capacity, BuildingCapacity(residents: 5, jobs: 56))
        XCTAssertEqual(PlacedBuildingKind.allCases.filter(\.standsOnShore), [.wharf, .marina])
        let before = world
        // On land (rows 5 and below, away from the river), or out at sea.
        for point in [PlanPoint(x: 14_336, y: 30_720), PlanPoint(x: 14_336, y: 8_192)] {
            XCTAssertThrowsError(try world.placeBuilding(.wharf, at: point)) { XCTAssertEqual($0 as? GameError, .needsShore) }
            XCTAssertThrowsError(try world.placeBuilding(.marina, at: point)) { XCTAssertEqual($0 as? GameError, .needsShore) }
        }
        XCTAssertEqual(world, before)
        // A wharf is 1,536 (24 m) a side: centred on row 5's north edge
        // (y 20,480) it spans rows 4, the sea, and 5, the land.
        let wharf = try world.placeBuilding(.wharf, at: PlanPoint(x: 14_336, y: 20_480))
        XCTAssertEqual(wharf.kind.use, .commercial)
        // A marina, 2,048 (32 m), across the river's west bank (x 40,960).
        let marina = try world.placeBuilding(.marina, at: PlanPoint(x: 40_960, y: 61_440))
        XCTAssertEqual(marina.kind.use, .leisure)
        // A house there is still on water.
        XCTAssertThrowsError(try world.placeBuilding(.house, at: PlanPoint(x: 18_432, y: 20_480))) {
            XCTAssertEqual($0 as? GameError, .onWater(row: 4, column: 4))
        }
        // A world without water has no shore.
        var dry = GameWorld(bounds: Self.small, economy: GameEconomy(balance: 0, costs: testCosts))
        XCTAssertThrowsError(try dry.placeBuilding(.marina, at: PlanPoint(x: 14_336, y: 20_480))) { XCTAssertEqual($0 as? GameError, .needsShore) }
    }

    /// Land within 160 m of water (10,240 units between the middles, the
    /// water's own cells too) is worth 600 cents a m² more.
    func testLandByTheWaterIsWorthMore() throws {
        let world = try world()
        func premium(_ row: Int, _ column: Int) -> Int64? {
            world.landValue(row: row, column: column)?.waterPremium
        }
        XCTAssertEqual(premium(5, 5), 600, "64 m from the sea")
        XCTAssertEqual(premium(6, 5), 600, "128 m")
        XCTAssertEqual(premium(7, 5), 0, "192 m")
        XCTAssertEqual(premium(7, 8), 600, "128 m from the river")
        XCTAssertEqual(premium(7, 7), 0, "192 m from the river and the sea")
        // (6, 8): 128 m from the sea and from the river; (8, 9) beside the
        // river.
        XCTAssertEqual(premium(6, 8), 600)
        XCTAssertEqual(premium(8, 9), 600)
        XCTAssertEqual(premium(2, 2), 600, "the sea itself")
        let value = try XCTUnwrap(world.landValue(row: 7, column: 8))
        XCTAssertEqual(value.value, value.base + value.servicePremium + value.accessPremium + 600)
        // A blank map's land is worth what it was.
        let blank = GameWorld(bounds: Self.small, economy: GameEconomy(balance: 0, costs: testCosts))
        XCTAssertEqual(blank.landValues().map(\.waterPremium).max(), 0)
        // Every cell agrees with working it out the long way.
        let wet = (0..<24).flatMap { row in (0..<32).filter { world.isWater(row: row, column: $0) }.map { (row, $0) } }
        for row in 0..<24 {
            for column in 0..<32 {
                let near = wet.contains { let (dr, dc) = (Int64($0.0 - row) * 4_096, Int64($0.1 - column) * 4_096); return dr * dr + dc * dc < 10_240 * 10_240 }
                XCTAssertEqual(premium(row, column), near ? 600 : 0, "(\(row), \(column))")
            }
        }
    }

    func testTrackAndStationsStillCrossWater() throws {
        var world = try world()
        // Over the sea, from (5, 5) north to row 1.
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 20_480, y: 8_192, z: 0))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 20_480, y: 24_576, z: 0))
        _ = try world.buildTrackEdge(from: a, to: b)
        let pier = try world.buildStation(named: "Pier", at: PlanPoint(x: 20_480, y: 8_192))
        XCTAssertTrue(world.isWater(row: Land.cellIndex(pier.point.y), column: Land.cellIndex(pier.point.x)))
    }

    // MARK: - Land read as it is needed

    /// Two blocks of land, (0, 0) and (0, 1), with a river along row 3
    /// across the edge between them (columns 10 to 20) and a cell of land
    /// in each.
    private func readTwoBlocks(_ order: [Int]) throws -> GameWorld {
        var world = GameWorld(bounds: Self.blocks, economy: GameEconomy(balance: 0, costs: testCosts))
        world.setLandOnDemand()
        for index in order {
            let block = LandBlock(row: 0, column: index)
            let columns = index == 0 ? 10...15 : 16...20
            try world.expandLand(
                [block], cells: [LandCell(row: 5, column: index * 16 + 1, use: .residential, residents: 10, jobs: 0)],
                water: cells(3...3, columns)
            )
        }
        return world
    }

    func testWaterReadWithTheBlocksIsTheSameInAnyOrder() throws {
        let eastFirst = try readTwoBlocks([1, 0]), westFirst = try readTwoBlocks([0, 1])
        XCTAssertEqual(eastFirst.terrain, westFirst.terrain)
        XCTAssertEqual(westFirst.terrain.water, [WaterRun(row: 3, column: 10, count: 11)])
        XCTAssertEqual(eastFirst.land, westFirst.land)
        // Starting again clears it.
        var again = westFirst
        again.setLandOnDemand()
        XCTAssertTrue(again.terrain.isEmpty)
    }

    func testBadWaterInABlockIsRefusedAndGrownLandStays() throws {
        var world = GameWorld(bounds: Self.blocks, economy: GameEconomy(balance: 0, costs: testCosts))
        world.setLandOnDemand()
        let before = world
        let block = LandBlock(row: 0, column: 0)
        for (cells, water) in [
            ([LandCell](), [CellPosition(row: 3, column: 16)]),  // in block (0, 1)
            ([], [CellPosition(row: 3, column: 3), CellPosition(row: 3, column: 3)]),
            ([LandCell(row: 3, column: 3, use: .residential, residents: 1, jobs: 0)], [CellPosition(row: 3, column: 3)]),
        ] {
            XCTAssertThrowsError(try world.expandLand([block], cells: cells, water: water)) {
                XCTAssertEqual($0 as? GameError, .invalidTerrain)
            }
        }
        XCTAssertEqual(world, before)
        // The town grew onto (3, 3) before its block was read: it stays land.
        world.addLand(LandCell(row: 3, column: 3, use: .residential, residents: 4, jobs: 0))
        try world.expandLand([block], cells: [], water: cells(3...3, 2...4))
        XCTAssertEqual(world.terrain.water, [WaterRun(row: 3, column: 2, count: 1), WaterRun(row: 3, column: 4, count: 1)])
        XCTAssertEqual(world.land.cell(row: 3, column: 3)?.residents, 4)
        XCTAssertNil(world.terrainProblem())
    }

    // MARK: - Saving

    func testWaterIsSavedAsRunsAndBadOnesAreRefused() throws {
        let world = try world()
        let data = try JSONEncoder().encode(world)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let terrain = try XCTUnwrap(object["terrain"] as? [String: Any])
        // Rows 0 to 4 whole, and column 10 of rows 5 to 23.
        XCTAssertEqual((terrain["water"] as? [Any])?.count, 5 + 19)
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: data), world)
        // A world without water writes none.
        let dry = try JSONEncoder().encode(GameWorld(bounds: Self.small, economy: GameEconomy(balance: 0, costs: testCosts)))
        XCTAssertFalse(String(decoding: dry, as: UTF8.self).contains("terrain"))

        func decodes(_ water: String, land: String? = nil, blocks: String? = nil) -> Bool {
            var world = object
            world["terrain"] = try! JSONSerialization.jsonObject(with: Data(#"{"water": \#(water)}"#.utf8))
            if let land { world["land"] = try! JSONSerialization.jsonObject(with: Data(land.utf8)) }
            if let blocks { world["landBlocks"] = try! JSONSerialization.jsonObject(with: Data(blocks.utf8)) }
            return (try? JSONDecoder().decode(GameWorld.self, from: JSONSerialization.data(withJSONObject: world))) != nil
        }
        XCTAssertTrue(decodes(#"[{"row": 0, "column": 0, "count": 2}, {"row": 0, "column": 3, "count": 1}]"#))
        XCTAssertFalse(decodes(#"[{"row": 0, "column": 0, "count": 2}, {"row": 0, "column": 2, "count": 1}]"#), "touching runs are one")
        XCTAssertFalse(decodes(#"[{"row": 1, "column": 0, "count": 1}, {"row": 0, "column": 0, "count": 1}]"#), "out of order")
        XCTAssertFalse(decodes(#"[{"row": 0, "column": 0, "count": 0}]"#), "empty")
        XCTAssertFalse(decodes(#"[{"row": 0, "column": 30, "count": 3}]"#), "past the world's edge")
        XCTAssertFalse(decodes(#"[{"row": 5, "column": 5, "count": 1}]"#), "land is there")
        XCTAssertFalse(decodes(#"[{"row": 0, "column": 0, "count": 1}]"#, blocks: #"[{"row": 1, "column": 0, "count": 1}]"#), "outside the blocks read")
    }

    private static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("SaveFixtures")

    /// The version 25 fixture (decision 111): the version 24 world, the
    /// zoning fixture's land and station (``ZoningTests``) by the sea, rows
    /// 0 to 2, with a river down column 10 below it; homes zoned from the
    /// sea onto the land on rows 2 to 3, a house bought beside the river
    /// (its land now by the water) and a marina across its west bank, run
    /// ten minutes.
    static func shoreWorld() throws -> GameWorld {
        var world = try GameWorld(
            bounds: WorldBounds(width: 131_072, height: 98_304), economy: GameEconomy(balance: 1_000_000_000, costs: testCosts),
            clock: GameClock(speed: .normal)
        )
        let sea = (0...2).flatMap { row in (0...31).map { CellPosition(row: row, column: $0) } }
        let river = (3...23).map { CellPosition(row: $0, column: 10) }
        try world.setWater(sea + river)
        try world.setLand([LandCell(row: 5, column: 5, use: .residential, residents: 1_000, jobs: 0)])
        world.setEconomyMode(.management)
        world.setLandDemand(true)
        world.setTownGrowth(true)
        try world.buildStation(named: "S0", at: PlanPoint(x: 22_528, y: 22_528))
        try world.placeBuilding(.house, at: PlanPoint(x: 40_448, y: 26_624))
        try world.placeBuilding(.marina, at: PlanPoint(x: 40_960, y: 61_440))
        try world.setZone(.residential, rows: 2...3, columns: 3...7)
        try world.advance(ticks: 10)
        return world
    }

    /// Version 24 (decision 105): the water. It saves byte for byte. Its
    /// builder is ``shoreWorld()`` without the marina; since decision 111
    /// land by the water is worth more, so the house would cost more now,
    /// and the test checks the save as it reads. The version 23 save has
    /// none.
    func testVersionTwentyFourKeepsTheWater() throws {
        let data = try Data(contentsOf: Self.fixtures.appendingPathComponent("v24-water.json"))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 24)
        let world = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(world.terrain.waterCellCount, 3 * 32 + 21)
        XCTAssertEqual(world.zones.cells.count, 5, "row 2 is the sea")
        XCTAssertEqual(world.placedBuildings.map(\.kind), [.house])
        XCTAssertEqual(world.placedBuildings.first?.landCost, 256_000, "256 m² at the empty land's 1,000, as it was paid")
        XCTAssertEqual(try encoder.encode(SavedGame(world: world)), Data(String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #""saveVersion" : 24,"#, with: #""saveVersion" : \#(SavedGame.currentVersion),"#).utf8))

        let older = try Data(contentsOf: Self.fixtures.appendingPathComponent("v23-zoning.json"))
        XCTAssertTrue(try JSONDecoder().decode(SavedGame.self, from: older).world.terrain.isEmpty)
    }

    /// Version 25 (decision 111): a placed building can be a wharf or a
    /// marina, on the shore. It saves byte for byte and is the world the
    /// build that wrote it makes. The version 24 save has neither.
    func testVersionTwentyFiveKeepsTheShoreBuildings() throws {
        let url = Self.fixtures.appendingPathComponent("v25-shore-buildings.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["SHORE_SAVE_NEW"] != nil {
            try encoder.encode(SavedGame(world: try Self.shoreWorld())).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 25)
        let world = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(world, try Self.shoreWorld())
        XCTAssertEqual(world.placedBuildings.map(\.kind), [.house, .marina])
        // 256 and 1,024 m² at 1,600 a m², the empty land's 1,000 and 600 by
        // the water.
        XCTAssertEqual(world.placedBuildings.map(\.landCost), [409_600, 1_638_400])
        XCTAssertEqual(try encoder.encode(SavedGame(world: world)), Data(String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #""saveVersion" : 25,"#, with: #""saveVersion" : \#(SavedGame.currentVersion),"#).utf8))
    }
}
