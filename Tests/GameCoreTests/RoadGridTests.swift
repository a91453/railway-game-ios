import Foundation
@testable import GameCore
import XCTest

/// The roads on the land's grid (decision 400 B.1–B.3): a town's first
/// square, the base map's roads by block, the monthly growth toward the
/// stations and the station road the player pays for. Every expectation is
/// worked out by hand from the rules; a cell is 4,096 units (64 m).
final class RoadGridTests: XCTestCase {
    private let cell = Land.cellLength

    /// A point in the middle of cell `row`, `column`.
    private func middle(_ row: Int, _ column: Int) -> PlanPoint {
        PlanPoint(x: Int64(column) * cell + cell / 2, y: Int64(row) * cell + cell / 2)
    }

    /// A managed world of 32 × 16 cells (2,048 × 1,024 m), ten minutes a
    /// tick, with a town in cell (8, 10).
    private func world(balance: Money = 1_000_000_000) throws -> GameWorld {
        var world = GameWorld(bounds: try WorldBounds(width: 32 * cell, height: 16 * cell), economy: GameEconomy(balance: balance, costs: testCosts),
                              clock: GameClock(speed: .fast))
        world.setEconomyMode(.management)
        world.enableRoads(towns: [middle(8, 10)])
        return world
    }

    /// The cells from row `rows` and columns `columns`.
    private func cells(_ rows: ClosedRange<Int>, _ columns: ClosedRange<Int>) -> Set<CellPosition> {
        Set(rows.flatMap { row in columns.map { CellPosition(row: row, column: $0) } })
    }

    /// Runs the world to the first minute of day `day`.
    private func run(_ world: inout GameWorld, toDay day: Int64) throws {
        let ticks = (day * GameTime.secondsPerDay - world.clock.now.seconds) / 600 + 1
        try world.advance(ticks: Int(ticks))
    }

    // MARK: - Off

    func testAWorldStartsWithNoRoads() throws {
        var world = try makeWorld()
        XCTAssertNil(world.roads)
        let station = try world.buildStation(named: "A", at: PlanPoint(x: 1_000, y: 1_000))
        XCTAssertThrowsGameError(try world.stationRoadQuote(at: station.id), .roadsNotEnabled)
        XCTAssertThrowsGameError(try world.buildStationRoad(at: station.id), .roadsNotEnabled)
        XCTAssertThrowsGameError(try world.setRoads([], in: []), .roadsNotEnabled)
    }

    // MARK: - Towns

    func testATownStartsWithASquareOfRoads() throws {
        let world = try world()
        XCTAssertEqual(world.roads?.cells, cells(7...9, 9...11))
        XCTAssertEqual(world.roads?.towns, [CellPosition(row: 8, column: 10)])
        // By the world's corner only the cells in it; off the world none;
        // a second town in the same cell is the first.
        var corner = world
        corner.enableRoads(towns: [PlanPoint(x: 0, y: 0), PlanPoint(x: 40 * cell, y: 0), PlanPoint(x: cell / 2, y: cell / 2)])
        XCTAssertEqual(corner.roads?.cells, cells(0...1, 0...1))
        XCTAssertEqual(corner.roads?.towns, [CellPosition(row: 0, column: 0)])
    }

    func testATownsRoadsLeaveOutTheWater() throws {
        var world = try world()
        try world.setWater([CellPosition(row: 7, column: 9)])
        world.enableRoads(towns: [middle(8, 10)])
        XCTAssertEqual(world.roads?.cells.count, 8)
        XCTAssertEqual(world.roads?.hasRoad(row: 7, column: 9), false)
    }

    // MARK: - The base map's roads

    func testTheBaseMapsRoadsComeInByBlock() throws {
        var world = try world()
        world.enableRoads()
        // Block (0, 1) holds columns 16 to 31.
        let block = LandBlock(row: 0, column: 1)
        try world.setRoads([CellPosition(row: 3, column: 20), CellPosition(row: 3, column: 21)], in: [block])
        XCTAssertEqual(world.roads?.cells, [CellPosition(row: 3, column: 20), CellPosition(row: 3, column: 21)])
        XCTAssertEqual(world.roads?.readBlocks, [block])
        // A road outside the blocks, or a block outside the world: nothing changes.
        let before = world
        XCTAssertThrowsGameError(try world.setRoads([CellPosition(row: 3, column: 2)], in: [block]), .invalidRoads)
        XCTAssertThrowsGameError(try world.setRoads([], in: [LandBlock(row: 0, column: 2)]), .invalidRoads)
        XCTAssertEqual(world, before)
        // Reading again keeps what is there.
        try world.setRoads([CellPosition(row: 4, column: 1)], in: [LandBlock(row: 0, column: 0)])
        XCTAssertEqual(world.roads?.cells.count, 3)
    }

    // MARK: - Station roads

    func testAStationRoadRunsToTheNearestRoadAtFiftyDollarsAMetre() throws {
        var world = try world()
        let station = try world.buildStation(named: "East", at: middle(8, 15))
        let balance = world.economy.balance
        // Four cells west to (8, 11): 256 m, $12,800.
        let quote = try world.stationRoadQuote(at: station.id)
        XCTAssertEqual(quote.joins, CellPosition(row: 8, column: 11))
        XCTAssertEqual(quote.cells, (12...15).reversed().map { CellPosition(row: 8, column: $0) })
        XCTAssertEqual(quote.metres, 256)
        XCTAssertEqual(quote.price, Money(1_280_000))
        XCTAssertEqual(try world.buildStationRoad(at: station.id), quote)
        XCTAssertEqual(world.economy.balance, balance - Money(1_280_000))
        XCTAssertEqual(world.accounts.capitalDays.last?.capitalSpending, Money(1_281_000), "with the station's $10")
        XCTAssertTrue(world.roads?.cells.isSuperset(of: quote.cells) == true)
        XCTAssertThrowsGameError(try world.stationRoadQuote(at: station.id), .stationOnRoad(station.id))
    }

    func testAStationRoadGoesCornerToCornerFirst() throws {
        var world = try world()
        let station = try world.buildStation(named: "South-east", at: middle(11, 14))
        // To (9, 11): two cells corner to corner and one straight, 244 m.
        let quote = try world.stationRoadQuote(at: station.id)
        XCTAssertEqual(quote.joins, CellPosition(row: 9, column: 11))
        XCTAssertEqual(quote.cells, [CellPosition(row: 11, column: 14), CellPosition(row: 10, column: 13), CellPosition(row: 9, column: 12)])
        XCTAssertEqual(quote.metres, 2 * 90 + 64)
        XCTAssertEqual(quote.price, Money(244 * 5_000))
    }

    func testAStationRoadReachesFiveHundredAndTwelveMetresAtMost() throws {
        var world = try world()
        let edge = try world.buildStation(named: "Edge", at: middle(8, 19))
        XCTAssertEqual(try world.stationRoadQuote(at: edge.id).metres, 512)
        let far = try world.buildStation(named: "Far", at: middle(8, 20))
        let before = world
        XCTAssertThrowsGameError(try world.buildStationRoad(at: far.id), .roadTooFar)
        XCTAssertEqual(world, before)
        XCTAssertThrowsGameError(try world.buildStationRoad(at: StationID(rawValue: 9)), .unknownStation(StationID(rawValue: 9)))
    }

    func testAStationRoadIsPaidForOrNotBuilt() throws {
        var world = try world(balance: Money(1_000_000))
        let station = try world.buildStation(named: "East", at: middle(8, 15))
        let before = world
        XCTAssertThrowsGameError(try world.buildStationRoad(at: station.id),
                                 .insufficientFunds(required: Money(1_280_000), available: world.economy.balance))
        XCTAssertEqual(world, before)
    }

    func testAStationRoadDoesNotCrossWater() throws {
        var world = try world()
        try world.setWater([CellPosition(row: 8, column: 13)])
        let station = try world.buildStation(named: "East", at: middle(8, 15))
        XCTAssertThrowsGameError(try world.stationRoadQuote(at: station.id), .onWater(row: 8, column: 13))
    }

    // MARK: - Growth

    func testATownsRoadsGrowACellAMonthTowardItsNearestStation() throws {
        var world = try world()
        try world.buildStation(named: "Far", at: middle(8, 20))
        let start = world.roads
        try run(&world, toDay: 29)
        XCTAssertEqual(world.roads, start, "nothing grows before the month is out")
        // From (8, 11), the road cell nearest (8, 20), to (8, 12): of
        // (7, 12), (8, 12) and (9, 12) the nearest the station.
        try run(&world, toDay: 30)
        XCTAssertEqual(world.roads?.cells, cells(7...9, 9...11).union([CellPosition(row: 8, column: 12)]))
        try run(&world, toDay: 60)
        XCTAssertEqual(world.roads?.cells.subtracting(cells(7...9, 9...11)), [CellPosition(row: 8, column: 12), CellPosition(row: 8, column: 13)])
    }

    func testARoadGrowsIntoWherePeopleLiveFirst() throws {
        var world = try world()
        try world.setLand([LandCell(row: 7, column: 12, use: .residential, residents: 10, jobs: 0)])
        world.enableRoads(towns: [middle(8, 10)])
        try world.buildStation(named: "Far", at: middle(8, 20))
        try run(&world, toDay: 30)
        XCTAssertEqual(world.roads?.cells.subtracting(cells(7...9, 9...11)), [CellPosition(row: 7, column: 12)])
    }

    func testRoadsStopAtTheStationAndSkipWater() throws {
        var world = try world()
        try world.setWater([CellPosition(row: 8, column: 12)])
        world.enableRoads(towns: [middle(8, 10)])
        try world.buildStation(named: "Near", at: middle(8, 13))
        // (8, 12) is water: (7, 12) and (9, 12) are as near; the lower row.
        try run(&world, toDay: 30)
        XCTAssertEqual(world.roads?.cells.subtracting(cells(7...9, 9...11)), [CellPosition(row: 7, column: 12)])
        try run(&world, toDay: 60)
        XCTAssertEqual(world.roads?.hasRoad(row: 8, column: 13), true, "the station's own cell")
        let reached = world.roads
        try run(&world, toDay: 90)
        XCTAssertEqual(world.roads, reached, "a station reached draws no more")
    }

    func testOnAMapWithNoTownsEachStationDrawsTheNearestRoad() throws {
        var world = try world()
        world.enableRoads()
        try world.setRoads([CellPosition(row: 3, column: 3)], in: [LandBlock(row: 0, column: 0)])
        try world.buildStation(named: "A", at: middle(3, 8))
        try world.buildStation(named: "B", at: middle(9, 3))
        try run(&world, toDay: 30)
        XCTAssertEqual(world.roads?.cells, [CellPosition(row: 3, column: 3), CellPosition(row: 3, column: 4), CellPosition(row: 4, column: 3)])
    }

    func testGrowthIsTheSameInOneBatchOrMany() throws {
        var once = try world()
        try once.buildStation(named: "Far", at: middle(2, 28))
        var often = once
        try once.advance(ticks: 3 * 144 * 30 + 1)
        for _ in 0..<(3 * 30) { try often.advance(ticks: 144) }
        try often.advance(ticks: 1)
        XCTAssertEqual(once.roads, often.roads)
        XCTAssertEqual(once.roads?.cells.count, 9 + 3)
    }

    // MARK: - Bought tiles

    /// A blank world of 5 × 5 tiles owning the middle one, its towns and
    /// roads drawn from seed 7 as a new game's are (all three in the
    /// middle tile), and tile (2, 3), east of it, bought.
    private func boughtWorld() throws -> (world: GameWorld, tile: MapTile) {
        let length = MapExpansion.tileLength
        var world = GameWorld(bounds: try WorldBounds(width: 5 * length, height: 5 * length),
                              economy: GameEconomy(balance: 1_000_000_000, costs: testCosts), clock: GameClock(speed: .fast))
        world.setEconomyMode(.management)
        world.enableRoads(towns: Land.townCentres(seed: 7, in: world.bounds))
        try world.enableMapExpansion(owning: MapTile(row: 2, column: 2), townSeed: 7)
        let tile = MapTile(row: 2, column: 3)
        try world.buyMapTile(tile, passingMilestone: true)
        return (world, tile)
    }

    /// The middle cells of the towns tile `tile` grows from seed 7.
    private func townCells(of tile: MapTile) -> [CellPosition] {
        let length = MapExpansion.tileLength
        return Land.townCentres(seed: MapExpansion.townSeed(of: tile, from: 7), in: .standard).map {
            CellPosition(row: Int((Int64(tile.row) * length + $0.y) / cell), column: Int((Int64(tile.column) * length + $0.x) / cell))
        }
    }

    func testABoughtTilesTownsStartWithASquareOfRoads() throws {
        let (world, tile) = try boughtWorld()
        let towns = townCells(of: tile)
        XCTAssertEqual(towns.count, 3)
        XCTAssertEqual(world.roads?.towns.suffix(3), towns[...], "the tile's towns grow after the first three")
        for town in towns {
            XCTAssertTrue(cells((town.row - 1)...(town.row + 1), (town.column - 1)...(town.column + 1)).isSubset(of: world.roads?.cells ?? []))
        }
    }

    func testABoughtTilesStationsGetTheirRoads() throws {
        var (world, tile) = try boughtWorld()
        // Twelve cells east of the tile's first town: eleven from its
        // square, past a station road's eight.
        let town = townCells(of: tile)[0]
        let station = try world.buildStation(named: "East", at: middle(town.row, town.column + 12))
        XCTAssertThrowsGameError(try world.stationRoadQuote(at: station.id), .roadTooFar)
        // The only station is every town's nearest: each of the six draws
        // a cell toward it, from the tile's square.
        try run(&world, toDay: 30)
        XCTAssertEqual(world.roads?.hasRoad(row: town.row, column: town.column + 2), true, "a cell toward the station")
        XCTAssertNoThrow(try world.stationRoadQuote(at: station.id), "within a station road's reach")
    }

    func testAStationNoTownIsNearestDrawsTheNearestRoad() throws {
        var world = try world()
        try world.buildStation(named: "Far", at: middle(8, 20))
        try world.buildStation(named: "Farther", at: middle(2, 30))
        // The town grows toward Far, (8, 12); then Farther draws the road
        // cell nearest it, (8, 12), toward it: (7, 13).
        try run(&world, toDay: 30)
        XCTAssertEqual(world.roads?.cells.subtracting(cells(7...9, 9...11)), [CellPosition(row: 8, column: 12), CellPosition(row: 7, column: 13)])
        // From (7, 13), now nearest Far, to (8, 14); from (8, 14), now
        // nearest Farther, to (7, 15).
        try run(&world, toDay: 60)
        XCTAssertEqual(world.roads?.cells.subtracting(cells(7...9, 9...11)), [
            CellPosition(row: 8, column: 12), CellPosition(row: 7, column: 13), CellPosition(row: 8, column: 14), CellPosition(row: 7, column: 15),
        ])
    }

    func testAnOldSaveGetsItsBoughtTilesRoads() throws {
        let (world, tile) = try boughtWorld()
        // A save of version 72 bought the tile with no roads for its towns.
        var old = world
        old.roads?.towns.removeLast(3)
        old.roads?.cells = Set(try XCTUnwrap(world.roads).cells.filter { MapExpansion.tile(ofCellRow: $0.row, column: $0.column) != tile })
        var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(SavedGame(world: old))) as? [String: Any])
        object["saveVersion"] = 72
        let loaded = try JSONDecoder().decode(SavedGame.self, from: JSONSerialization.data(withJSONObject: object)).world
        XCTAssertEqual(loaded.roads, world.roads)
        // Loaded again, nothing more.
        let again = try JSONDecoder().decode(SavedGame.self, from: JSONEncoder().encode(SavedGame(world: loaded))).world
        XCTAssertEqual(again, loaded)
    }

    // MARK: - Saves

    func testVersionSeventyTwoKeepsTheRoads() throws {
        var world = try world()
        let station = try world.buildStation(named: "East", at: middle(8, 15))
        try world.buildStationRoad(at: station.id)
        try world.buildStation(named: "North", at: middle(5, 10))
        try world.setRoads([CellPosition(row: 2, column: 20)], in: [LandBlock(row: 0, column: 1)])
        try run(&world, toDay: 30)

        let url = SavedGameTests.fixtures.appendingPathComponent("v72-roads.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["ROADS_SAVE_NEW"] != nil {
            try encoder.encode(SavedGame(world: world)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 72)
        let loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(loaded, world)
        // The town's square, the station road and the month's cell toward
        // North, (6, 10), and the base map's cell.
        XCTAssertEqual(loaded.roads?.cells, cells(7...9, 9...11).union((12...15).map { CellPosition(row: 8, column: $0) })
            .union([CellPosition(row: 6, column: 10), CellPosition(row: 2, column: 20)]))
        XCTAssertEqual(loaded.roads?.readBlocks, [LandBlock(row: 0, column: 1)])
        XCTAssertEqual(try encoder.encode(SavedGame(world: loaded)), Data(String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #""saveVersion" : 72,"#, with: #""saveVersion" : \#(SavedGame.currentVersion),"#).utf8))
        // Without the key there are no roads.
        var plain = object
        var saved = try XCTUnwrap(plain["world"] as? [String: Any])
        saved["roads"] = nil
        plain["world"] = saved
        let off = try JSONDecoder().decode(SavedGame.self, from: JSONSerialization.data(withJSONObject: plain)).world
        XCTAssertNil(off.roads)
    }

    func testDamagedRoadsAreRefused() throws {
        let world = try world()
        let encoder = JSONEncoder()
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: encoder.encode(SavedGame(world: world))) as? [String: Any])
        func load(_ roads: Any) throws {
            var plain = object
            var saved = try XCTUnwrap(plain["world"] as? [String: Any])
            saved["roads"] = roads
            plain["world"] = saved
            _ = try JSONDecoder().decode(SavedGame.self, from: JSONSerialization.data(withJSONObject: plain))
        }
        XCTAssertNoThrow(try load(["cells": [["row": 0, "column": 0, "count": 32]]]))
        XCTAssertThrowsError(try load(["cells": [["row": 0, "column": 0, "count": 33]]]), "past the world's edge")
        XCTAssertThrowsError(try load(["cells": [["row": 0, "column": 0, "count": 0]]]), "an empty run")
        XCTAssertThrowsError(try load(["cells": [["row": 0, "column": Int.max - 1, "count": 5]]]), "a run past the largest column")
        XCTAssertThrowsError(try load(["cells": [["row": Int.max, "column": 0, "count": 1]]]), "a row past the largest")
        XCTAssertThrowsError(try load(["cells": [["row": 1, "column": 0, "count": 1], ["row": 0, "column": 0, "count": 1]]]), "out of order")
        XCTAssertThrowsError(try load(["cells": [["row": 0, "column": 0, "count": 3], ["row": 0, "column": 2, "count": 1]]]), "overlapping")
        XCTAssertThrowsError(try load(["towns": [["row": 16, "column": 0]]]), "a town outside the world")
        XCTAssertThrowsError(try load(["towns": [["row": 8, "column": 10], ["row": 8, "column": 10]]]), "a town twice")
        XCTAssertThrowsError(try load(["blocks": [["row": 0, "column": 2, "count": 1]]]), "a block outside the world")
    }

    /// Decision 400's later point 2: a damaged file naming more road cells
    /// or read blocks than the world has is refused before they are spread
    /// out. The world has 32 × 16 = 512 cells and 2 blocks.
    func testMoreRoadsThanTheWorldHasAreRefusedUnread() throws {
        let world = try world()
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(SavedGame(world: world))) as? [String: Any])
        func refusal(_ roads: Any) -> String? {
            var plain = object
            var saved = object["world"] as? [String: Any] ?? [:]
            saved["roads"] = roads
            plain["world"] = saved
            do {
                _ = try JSONDecoder().decode(SavedGame.self, from: JSONSerialization.data(withJSONObject: plain))
                return nil
            } catch DecodingError.dataCorrupted(let context) {
                return context.debugDescription
            } catch {
                return "\(error)"
            }
        }
        XCTAssertNil(refusal(["cells": (0..<16).map { ["row": $0, "column": 0, "count": 32] }]), "every cell")
        XCTAssertEqual(refusal(["cells": (0..<17).map { ["row": $0, "column": 0, "count": 32] }]), "The roads are more cells than the world has.")
        // Runs of the widest world's rows, far past this world's cells.
        XCTAssertEqual(refusal(["cells": (0..<4_096).map { ["row": $0, "column": 0, "count": 8_192] }]), "The roads are more cells than the world has.")
        XCTAssertEqual(refusal(["blocks": [["row": 0, "column": 0, "count": 3]]]), "The blocks whose roads were read are more blocks than the world has.")
    }
}
