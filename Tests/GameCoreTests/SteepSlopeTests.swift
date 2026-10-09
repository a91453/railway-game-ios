import Foundation
@testable import GameCore
import XCTest

/// Steep slopes (ARCHITECTURE decision 112): hillsides of more than 30 %,
/// kept with the water in the terrain, where the city puts up nothing new
/// and raises nothing, and the player neither builds nor zones; land may
/// stand on them, and track still crosses them. Every number below is
/// worked out by hand.
final class SteepSlopeTests: XCTestCase {
    /// 32 × 24 cells.
    private static let small = try! WorldBounds(width: 131_072, height: 98_304)
    /// 64 × 64 cells, 4 × 4 blocks of land.
    private static let blocks = try! WorldBounds(width: 262_144, height: 262_144)

    private func cells(_ rows: ClosedRange<Int>, _ columns: ClosedRange<Int>) -> [CellPosition] {
        rows.flatMap { row in columns.map { CellPosition(row: row, column: $0) } }
    }

    /// A managed world with a mountain east of column 7 (columns 7 to 31)
    /// and a lake at rows 20 to 23, columns 0 to 3; one home cell at
    /// (5, 5), and town growth with the station S0 there, measured at 800.
    private func world() throws -> GameWorld {
        var world = GameWorld(bounds: Self.small, economy: GameEconomy(balance: 1_000_000_000, costs: testCosts), clock: GameClock(speed: .normal))
        try world.setWater(cells(20...23, 0...3))
        try world.setSteep(cells(0...23, 7...31))
        try world.setLand([LandCell(row: 5, column: 5, use: .residential, residents: 1_000, jobs: 0)])
        world.setEconomyMode(.management)
        world.setLandDemand(true)
        world.setTownGrowth(true)
        try world.buildStation(named: "S0", at: PlanPoint(x: 22_528, y: 22_528))
        world.growLand(reached: [:])
        world.townGrowth!.places[0].lastService = 800
        world.townGrowth!.places[0].lastReached = 2
        return world
    }

    // MARK: - The layer

    func testSteepSlopesAreRunsBesideTheWater() throws {
        let world = try world()
        XCTAssertEqual(world.terrain.steepCellCount, 24 * 25)
        XCTAssertEqual(world.terrain.steep.first, WaterRun(row: 0, column: 7, count: 25))
        XCTAssertEqual(world.terrain.waterCellCount, 16)
        XCTAssertTrue(world.isSteep(row: 12, column: 7))
        XCTAssertFalse(world.isSteep(row: 12, column: 6))
        XCTAssertFalse(world.isSteep(row: 21, column: 2), "the lake")
        XCTAssertEqual(Terrain(water: [], steep: [CellPosition(row: 1, column: 2), CellPosition(row: 1, column: 1)]).steep, [WaterRun(row: 1, column: 1, count: 2)])
        // Clearing the water keeps the slopes, and the other way round.
        var cleared = world
        try cleared.setWater([])
        XCTAssertEqual(cleared.terrain.steepCellCount, 24 * 25)
        try cleared.setSteep([])
        XCTAssertTrue(cleared.terrain.isEmpty)
    }

    func testBadSteepSlopesAreRefusedAndLandMayStandOnThem() throws {
        var world = try world()
        let before = world
        for bad in [
            [CellPosition(row: 24, column: 0)], [CellPosition(row: 0, column: -1)],
            [CellPosition(row: 1, column: 1), CellPosition(row: 1, column: 1)],
            [CellPosition(row: 21, column: 1)],  // the lake
        ] {
            XCTAssertThrowsError(try world.setSteep(bad)) { XCTAssertEqual($0 as? GameError, .invalidTerrain) }
        }
        // Water on a steep slope.
        XCTAssertThrowsError(try world.setWater([CellPosition(row: 1, column: 8)])) { XCTAssertEqual($0 as? GameError, .invalidTerrain) }
        XCTAssertEqual(world, before)
        // People live on hillsides: land on a steep slope is set.
        try world.setLand([LandCell(row: 5, column: 5, use: .residential, residents: 1_000, jobs: 0), LandCell(row: 5, column: 9, use: .residential, residents: 50, jobs: 0)])
        XCTAssertEqual(world.land.cell(row: 5, column: 9)?.residents, 50)
        XCTAssertNil(world.terrainProblem())
        // Land read as it is needed reads its slopes with its blocks.
        var onDemand = GameWorld(bounds: Self.blocks, economy: GameEconomy(balance: 0, costs: testCosts))
        onDemand.setLandOnDemand()
        XCTAssertThrowsError(try onDemand.setSteep([CellPosition(row: 0, column: 0)])) { XCTAssertEqual($0 as? GameError, .invalidTerrain) }
    }

    // MARK: - Rules

    func testTheTownDoesNotSpreadUpTheMountain() throws {
        var world = try world()
        for _ in 0..<60 {
            world.spread(towards: world.stations[0])
        }
        // S0's 800 m reaches columns 0 to 17; only 0 to 6 are not steep.
        XCTAssertEqual(world.land.cells.count, 61)
        XCTAssertFalse(world.land.cells.contains { $0.column >= 7 })
        XCTAssertFalse(world.land.cells.contains { world.isWater(row: $0.row, column: $0.column) })
    }

    func testNothingIsRaisedOnASteepSlope() throws {
        var world = try world()
        // 100 residents each: D1 homes, which can be raised.
        try world.setLand([LandCell(row: 5, column: 5, use: .residential, residents: 100, jobs: 0), LandCell(row: 5, column: 8, use: .residential, residents: 100, jobs: 0)])
        world.setCityBuildings(true)
        let flat = try XCTUnwrap(world.buildings.building(row: 5, column: 5)?.density)
        let hill = try XCTUnwrap(world.buildings.building(row: 5, column: 8)?.density)
        var raised: Set<CellPosition> = []
        world.raiseBuildings(around: world.stations[0], full: [CellPosition(row: 5, column: 5), CellPosition(row: 5, column: 8)], raised: &raised)
        XCTAssertEqual(raised, [CellPosition(row: 5, column: 5)])
        XCTAssertGreaterThan(try XCTUnwrap(world.buildings.building(row: 5, column: 5)?.density), flat)
        XCTAssertEqual(world.buildings.building(row: 5, column: 8)?.density, hill)
    }

    func testSteepSlopesAreNotZoned() throws {
        var world = try world()
        let before = world
        XCTAssertThrowsError(try world.setZone(.residential, rows: 2...4, columns: 8...10)) {
            XCTAssertEqual($0 as? GameError, .onSteepSlope(row: 2, column: 8))
        }
        XCTAssertEqual(world, before)
        // From the flat onto the mountain: columns 5 and 6 of rows 2 and 3.
        XCTAssertEqual(try world.setZone(.commercial, rows: 2...3, columns: 5...9), 4)
        XCTAssertEqual(world.zones.cells.map(\.position), cells(2...3, 5...6))
        // Water first: still onWater, as before decision 112.
        var wet = GameWorld(bounds: Self.small, economy: GameEconomy(balance: 0, costs: testCosts))
        try wet.setWater([CellPosition(row: 0, column: 0)])
        try wet.setSteep([CellPosition(row: 0, column: 1)])
        XCTAssertThrowsError(try wet.setZone(.office, rows: 0...0, columns: 0...1)) { XCTAssertEqual($0 as? GameError, .onWater(row: 0, column: 0)) }
    }

    func testABuildingCannotStandOnASteepSlope() throws {
        var world = try world()
        let before = world
        // A house (1,024 a side) centred on the mountain's west edge, x
        // 28,672, in the middle of row 10: half in column 6, half in 7.
        XCTAssertThrowsError(try world.placeBuilding(.house, at: PlanPoint(x: 28_672, y: 43_008))) {
            XCTAssertEqual($0 as? GameError, .onSteepSlope(row: 10, column: 7))
        }
        // A marina on the lake's east shore (x 16,384) at row 20's north
        // edge: water and flat land, no slope.
        XCTAssertEqual(world, before)
        let marina = try world.placeBuilding(.marina, at: PlanPoint(x: 16_384, y: 81_920))
        XCTAssertEqual(marina.kind, .marina)
        // Touching the mountain's edge from the west is flat.
        XCTAssertNoThrow(try world.placeBuilding(.house, at: PlanPoint(x: 28_160, y: 43_008)))
    }

    func testTownsOfAMapWithNoOneLeaveTheMountainOut() throws {
        var blank = GameWorld(bounds: Self.small, economy: GameEconomy(balance: 0, costs: testCosts))
        blank.foundTowns(seed: 1)
        let flat = blank.land.cells.filter { $0.column < 7 }
        XCTAssertLessThan(flat.count, blank.land.cells.count)
        var hilly = GameWorld(bounds: Self.small, economy: GameEconomy(balance: 0, costs: testCosts))
        try hilly.setSteep(cells(0...23, 7...31))
        hilly.foundTowns(seed: 1)
        XCTAssertEqual(hilly.land.cells, flat)
    }

    func testTrackStillClimbsTheMountain() throws {
        var world = try world()
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 20_480, y: 30_720, z: 0))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 61_440, y: 30_720, z: 0))
        _ = try world.buildTrackEdge(from: a, to: b)
        XCTAssertNoThrow(try world.buildStation(named: "Summit", at: PlanPoint(x: 61_440, y: 30_720)))
    }

    // MARK: - Land read as it is needed

    private func readTwoBlocks(_ order: [Int]) throws -> GameWorld {
        var world = GameWorld(bounds: Self.blocks, economy: GameEconomy(balance: 0, costs: testCosts))
        world.setLandOnDemand()
        for index in order {
            let columns = index == 0 ? 12...15 : 16...19
            try world.expandLand(
                [LandBlock(row: 0, column: index)], cells: [LandCell(row: 5, column: index * 16 + 13, use: .residential, residents: 10, jobs: 0)],
                water: index == 0 ? [CellPosition(row: 9, column: 2)] : [], steep: cells(5...5, columns)
            )
        }
        return world
    }

    func testSteepSlopesReadWithTheBlocksAreTheSameInAnyOrder() throws {
        let westFirst = try readTwoBlocks([0, 1]), eastFirst = try readTwoBlocks([1, 0])
        XCTAssertEqual(westFirst.terrain, eastFirst.terrain)
        XCTAssertEqual(westFirst.terrain.steep, [WaterRun(row: 5, column: 12, count: 8)])
        XCTAssertEqual(westFirst.land.cell(row: 5, column: 13)?.residents, 10, "land on a slope")
        XCTAssertNil(westFirst.terrainProblem())

        var world = GameWorld(bounds: Self.blocks, economy: GameEconomy(balance: 0, costs: testCosts))
        world.setLandOnDemand()
        let before = world
        for (water, steep) in [
            ([CellPosition](), [CellPosition(row: 0, column: 16)]),  // block (0, 1)
            ([], [CellPosition(row: 0, column: 0), CellPosition(row: 0, column: 0)]),
            ([CellPosition(row: 0, column: 0)], [CellPosition(row: 0, column: 0)]),
        ] {
            XCTAssertThrowsError(try world.expandLand([LandBlock(row: 0, column: 0)], cells: [], water: water, steep: steep)) {
                XCTAssertEqual($0 as? GameError, .invalidTerrain)
            }
        }
        XCTAssertEqual(world, before)
    }

    // MARK: - Saving

    func testSteepSlopesAreSavedAsRunsAndBadOnesAreRefused() throws {
        let world = try world()
        let data = try JSONEncoder().encode(world)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let terrain = try XCTUnwrap(object["terrain"] as? [String: Any])
        XCTAssertEqual((terrain["steep"] as? [Any])?.count, 24)
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: data), world)

        func decodes(_ steep: String) -> Bool {
            var world = object
            var terrain = terrain
            terrain["steep"] = try! JSONSerialization.jsonObject(with: Data(steep.utf8))
            world["terrain"] = terrain
            return (try? JSONDecoder().decode(GameWorld.self, from: JSONSerialization.data(withJSONObject: world))) != nil
        }
        XCTAssertTrue(decodes(#"[{"row": 0, "column": 7, "count": 2}]"#))
        XCTAssertFalse(decodes(#"[{"row": 0, "column": 7, "count": 2}, {"row": 0, "column": 9, "count": 1}]"#), "touching runs are one")
        XCTAssertFalse(decodes(#"[{"row": 21, "column": 1, "count": 1}]"#), "on the lake")
        XCTAssertFalse(decodes(#"[{"row": 0, "column": 30, "count": 3}]"#), "past the world's edge")
    }

    private static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("SaveFixtures")

    /// The version 26 fixture: the version 25 world (``TerrainTests``'s
    /// shore world) with a hillside east of column 20 (columns 20 to 31,
    /// rows 3 to 23) and a home cell of 50 on it at (6, 22), run ten
    /// minutes.
    static func slopeWorld() throws -> GameWorld {
        var world = try GameWorld(
            bounds: WorldBounds(width: 131_072, height: 98_304), economy: GameEconomy(balance: 1_000_000_000, costs: testCosts),
            clock: GameClock(speed: .normal)
        )
        let sea = (0...2).flatMap { row in (0...31).map { CellPosition(row: row, column: $0) } }
        let river = (3...23).map { CellPosition(row: $0, column: 10) }
        try world.setWater(sea + river)
        try world.setSteep((3...23).flatMap { row in (20...31).map { CellPosition(row: row, column: $0) } })
        try world.setLand([
            LandCell(row: 5, column: 5, use: .residential, residents: 1_000, jobs: 0), LandCell(row: 6, column: 22, use: .residential, residents: 50, jobs: 0),
        ])
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

    /// Version 26 (decision 112): the steep slopes. It saves byte for byte
    /// and is the world the build that wrote it makes. The version 25 save
    /// has none.
    func testVersionTwentySixKeepsTheSteepSlopes() throws {
        let url = Self.fixtures.appendingPathComponent("v26-steep-slopes.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["SLOPE_SAVE_NEW"] != nil {
            try encoder.encode(SavedGame(world: try Self.slopeWorld())).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 26)
        let world = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(world, try Self.slopeWorld())
        XCTAssertEqual(world.terrain.steepCellCount, 21 * 12)
        XCTAssertEqual(world.land.cell(row: 6, column: 22)?.residents, 50)
        XCTAssertEqual(try encoder.encode(SavedGame(world: world)), Data(String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #""saveVersion" : 26,"#, with: #""saveVersion" : \#(SavedGame.currentVersion),"#).utf8))

        let older = try Data(contentsOf: Self.fixtures.appendingPathComponent("v25-shore-buildings.json"))
        XCTAssertTrue(try JSONDecoder().decode(SavedGame.self, from: older).world.terrain.steep.isEmpty)
    }
}
