import Foundation
@testable import GameCore
import XCTest

/// The map grows (decision 969): a world reaches farther to the south and
/// the east, its north-west corner where it was, and everything in it
/// stays; a game played over a map that was whole keeps the tiles it had
/// when the map comes to be bought.
///
/// Expected values are worked out by hand from the rules and written out,
/// never taken from a previous run.
final class MapGrowthTests: XCTestCase {
    private let tile = MapExpansion.tileLength
    private let block = Land.blockLength
    /// A city's map: 16.8 blocks by 21.4, so its last column and row of
    /// blocks are cut, and 2 tiles by 2.
    private let small = try! WorldBounds(width: 1_100_000, height: 1_400_000)
    /// The same map grown to the next city: 4 tiles by 7.
    private let large = try! WorldBounds(width: 3_600_000, height: 7_300_000)
    private let anchor = GeoAnchor(latitude: 336_200_000, longitude: 1_303_850_000)!

    /// A managed world of the small map over the Earth, its land read in as
    /// it is needed.
    private func world(balance: Money = 100_000_000_000) throws -> GameWorld {
        var world = GameWorld(bounds: small, economy: fixtureEconomy(balance: balance, costs: testCosts), clock: GameClock(speed: .paused))
        world.setEconomyMode(.management)
        world.setGeoAnchor(anchor)
        world.setLandDemand(true)
        world.setCityBuildings(true)
        world.setLandOnDemand()
        return world
    }

    private func cell(_ row: Int, _ column: Int, residents: Int64 = 100) -> LandCell {
        LandCell(row: row, column: column, use: .residential, residents: residents, jobs: 0)
    }

    // MARK: - Growing

    func testTheWorldGrowsFromItsNorthWestCornerAndEverythingStays() throws {
        var world = try world()
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 500_000, y: 700_000))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 900_000, y: 700_000))
        let edge = try world.buildTrackEdge(from: a, to: b)
        let station = try world.buildStation(named: "Hakata", at: PlanPoint(x: 600_000, y: 705_000)).id
        try world.addTrackPlatform(station, on: edge, from: 80_000, to: 120_000)
        // The block round the station (row 10, column 9), whole, and the
        // one at the south-east corner (row 21, column 16), cut both ways:
        // the world ends in its cell row 5 (341.8 cells) and column 12.
        let inner = LandBlock(row: 10, column: 9), corner = LandBlock(row: 21, column: 16)
        try world.expandLand(
            [inner, corner], cells: [cell(165, 150, residents: 300), cell(337, 257, residents: 40)],
            water: [CellPosition(row: 161, column: 144), CellPosition(row: 336, column: 256)],
            steep: [CellPosition(row: 162, column: 144), CellPosition(row: 338, column: 258)]
        )
        let before = world
        try world.growMap(to: large)

        XCTAssertEqual(world.bounds, large)
        XCTAssertEqual(world.geoAnchor, anchor)
        XCTAssertEqual(world.geoAnchorBounds, small, "the anchor is the middle of the map as it was")
        XCTAssertEqual(world.stations, before.stations)
        XCTAssertEqual(world.network, before.network)
        XCTAssertEqual(world.land, before.land, "the cells read stay, those of the cut block too")
        XCTAssertEqual(world.buildings, before.buildings)
        XCTAssertEqual(world.economy, before.economy, "free")
        XCTAssertEqual(world.landBlocks, [inner], "the block the old edges cut is to be read again")
        XCTAssertTrue(world.terrain.isWater(row: 161, column: 144))
        XCTAssertTrue(world.terrain.isSteep(row: 162, column: 144))
        XCTAssertFalse(world.terrain.isWater(row: 336, column: 256), "its water comes back as it is read")
        XCTAssertFalse(world.terrain.isSteep(row: 338, column: 258))
        XCTAssertEqual(world.landCatchment(of: station)?.residents, before.landCatchment(of: station)?.residents)
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world)), world, "a world GameCore loads")

        // The cut block is read again: the cell it had keeps what it has,
        // the cells beyond the old edge come in.
        try world.expandLand(
            [corner], cells: [cell(337, 257, residents: 999), cell(350, 270, residents: 60)],
            water: [CellPosition(row: 336, column: 256), CellPosition(row: 351, column: 271)]
        )
        XCTAssertEqual(world.land.cell(row: 337, column: 257)?.residents, 40)
        XCTAssertEqual(world.land.cell(row: 350, column: 270)?.residents, 60)
        XCTAssertTrue(world.terrain.isWater(row: 336, column: 256))
        XCTAssertTrue(world.terrain.isWater(row: 351, column: 271))
        XCTAssertEqual(world.landBlocks, [inner, corner])

        // Ground beyond the old edge can be built on.
        XCTAssertNoThrow(try world.buildStation(named: "Kumamoto", at: PlanPoint(x: 2_000_000, y: 7_000_000)))
        var smaller = before
        XCTAssertThrowsGameError(
            try smaller.buildStation(named: "Kumamoto", at: PlanPoint(x: 2_000_000, y: 7_000_000)), .outOfBounds(PlanPoint(x: 2_000_000, y: 7_000_000))
        )
    }

    func testAMapThatGrowsTwiceKeepsTheAnchorItBeganWith() throws {
        var world = try world()
        let middle = try WorldBounds(width: 1_100_000, height: 3_000_000)
        try world.growMap(to: middle)
        XCTAssertEqual(world.geoAnchorBounds, small)
        try world.growMap(to: large)
        XCTAssertEqual(world.geoAnchorBounds, small)
        XCTAssertEqual(world.bounds, large)
        // Laid over the Earth anew, its anchor is the middle of all of it.
        world.setGeoAnchor(anchor)
        XCTAssertNil(world.geoAnchorBounds)
    }

    func testABlankMapGrowsWithoutAnAnchor() throws {
        var world = GameWorld(bounds: small, economy: GameEconomy(balance: 0))
        try world.growMap(to: large)
        XCTAssertEqual(world.bounds, large)
        XCTAssertNil(world.geoAnchorBounds)
    }

    func testTheSameSizeChangesNothingAndASmallerOneIsRefused() throws {
        var world = try world()
        let before = world
        try world.growMap(to: small)
        XCTAssertEqual(world, before)
        XCTAssertNil(world.geoAnchorBounds)
        let narrower = try WorldBounds(width: 1_099_999, height: 7_300_000)
        XCTAssertThrowsGameError(try world.growMap(to: narrower), .invalidMapSize(width: 1_099_999, height: 7_300_000))
        let shorter = try WorldBounds(width: 3_600_000, height: 1_399_999)
        XCTAssertThrowsGameError(try world.growMap(to: shorter), .invalidMapSize(width: 3_600_000, height: 1_399_999))
        XCTAssertEqual(world, before)
    }

    func testOnlyTheBlocksAnEdgeThatMovedCutAreReadAgain() throws {
        // 16.8 blocks by 21.4: columns 0...16, rows 0...21.
        let south = try WorldBounds(width: 1_100_000, height: 7_300_000)
        XCTAssertEqual(GameWorld.blocksCut(at: small, in: south), Set((0...16).map { LandBlock(row: 21, column: $0) }))
        let east = try WorldBounds(width: 3_600_000, height: 1_400_000)
        XCTAssertEqual(GameWorld.blocksCut(at: small, in: east), Set((0...21).map { LandBlock(row: $0, column: 16) }))
        XCTAssertEqual(GameWorld.blocksCut(at: small, in: large).count, 17 + 22 - 1)
        // A world of whole blocks has none cut.
        let whole = try WorldBounds(width: 16 * block, height: 16 * block)
        XCTAssertEqual(GameWorld.blocksCut(at: whole, in: large), [])
    }

    func testTheRoadsOfACutBlockAreReadAgain() throws {
        var world = try world()
        world.enableRoads()
        let inner = LandBlock(row: 10, column: 9), corner = LandBlock(row: 21, column: 16)
        try world.setRoads([CellPosition(row: 165, column: 150), CellPosition(row: 337, column: 257)], in: [inner, corner])
        try world.growMap(to: large)
        XCTAssertEqual(world.roads?.readBlocks, [inner])
        XCTAssertEqual(world.roads?.cells, [CellPosition(row: 165, column: 150), CellPosition(row: 337, column: 257)], "the roads read stay")
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world)), world)
    }

    // MARK: - Tiles

    func testAGamePlayedOverAWholeMapKeepsItsTilesAndBuysTheRest() throws {
        var world = try world()
        _ = try world.buildStation(named: "Airport", at: PlanPoint(x: 1_090_000, y: 600_000))
        _ = try world.buildStation(named: "South", at: PlanPoint(x: 300_000, y: 1_390_000))
        try world.growMap(to: large)
        let four = [MapTile(row: 0, column: 0), MapTile(row: 0, column: 1), MapTile(row: 1, column: 0), MapTile(row: 1, column: 1)]
        // One tile cannot hold what it built over the whole map.
        XCTAssertThrowsGameError(try world.enableMapExpansion(owning: MapTile(row: 0, column: 0), townSeed: nil, ridersStep: 20_000), .invalidMapTile)
        XCTAssertThrowsGameError(try world.enableMapExpansion(owning: [], townSeed: nil), .invalidMapTile)
        XCTAssertThrowsGameError(try world.enableMapExpansion(owning: four + [four[0]], townSeed: nil), .invalidMapTile)
        // Each tile is beside another.
        XCTAssertThrowsGameError(try world.enableMapExpansion(owning: four + [MapTile(row: 3, column: 1)], townSeed: nil), .invalidMapTile)
        XCTAssertNil(world.mapExpansion)

        let balance = world.economy.balance
        try world.enableMapExpansion(owning: [four[3], four[0], four[2], four[1]], townSeed: nil, ridersStep: 20_000)
        let expansion = try XCTUnwrap(world.mapExpansion)
        XCTAssertEqual(expansion.owned, four)
        XCTAssertEqual(expansion.granted, 4)
        XCTAssertEqual(expansion.bought, 0)
        XCTAssertEqual(world.economy.balance, balance, "the tiles it had are free")
        XCTAssertEqual(world.mapTileRows, 7)
        XCTAssertEqual(world.mapTileColumns, 4)
        XCTAssertFalse(world.ownsGround(at: PlanPoint(x: 300_000, y: 2 * tile)))
        XCTAssertEqual(world.mapTilesForSale(), [
            MapTile(row: 0, column: 2), MapTile(row: 1, column: 2), MapTile(row: 2, column: 0), MapTile(row: 2, column: 1),
        ])
        // The first it buys asks and costs what a new game's second does:
        // 20,000 riders, and $150 for each, $3,000,000.
        XCTAssertEqual(expansion.allowance, 4)
        XCTAssertEqual(expansion.ridersNeeded(toOwn: 4), 0)
        XCTAssertEqual(expansion.ridersNeeded(toOwn: 5), 20_000)
        XCTAssertEqual(expansion.nextPrice, 300_000_000)
        let south = MapTile(row: 2, column: 0)
        XCTAssertThrowsGameError(try world.buyMapTile(south), .mapExpansionLocked(ridersNeeded: 20_000))
        try world.buyMapTile(south, passingMilestone: true)
        XCTAssertEqual(world.economy.balance, balance - 300_000_000)
        XCTAssertEqual(world.mapExpansion?.bought, 1)
        XCTAssertEqual(world.mapExpansion?.nextPrice, 600_000_000)
        XCTAssertEqual(world.mapExpansion?.ridersNeeded(toOwn: 6), 40_000)
        XCTAssertTrue(world.ownsGround(at: PlanPoint(x: 300_000, y: 2 * tile)))

        let data = try JSONEncoder().encode(world)
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: data), world, "a world GameCore loads")
        let saved = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual((saved["mapExpansion"] as? [String: Any])?["granted"] as? Int, 4)
        XCTAssertEqual((saved["geoAnchorBounds"] as? [String: Any])?["width"] as? Int, 1_100_000)
    }

    func testANewGamesOneTileIsWrittenAsBeforeAndFewerThanOneIsRefused() throws {
        var world = try world()
        try world.enableMapExpansion(owning: MapTile(row: 0, column: 0), townSeed: nil)
        XCTAssertEqual(world.mapExpansion?.granted, 1)
        // As decision 160 priced it: the second tile costs one step.
        XCTAssertEqual(world.mapExpansion?.nextPrice, MapExpansion.priceStep)
        XCTAssertEqual(world.mapExpansion?.allowance, 1)
        XCTAssertEqual(MapExpansion.ridersNeeded(toOwn: 3), 200_000)
        let data = try JSONEncoder().encode(world)
        var saved = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var expansion = try XCTUnwrap(saved["mapExpansion"] as? [String: Any])
        XCTAssertNil(expansion["granted"])
        XCTAssertNil(saved["geoAnchorBounds"])
        for bad in [0, 2] {
            expansion["granted"] = bad
            saved["mapExpansion"] = expansion
            XCTAssertThrowsError(
                try JSONDecoder().decode(GameWorld.self, from: JSONSerialization.data(withJSONObject: saved)), "\(bad) given of one owned"
            )
        }
    }

    func testATilesRecordIsNumberedAgainAsTheMapGrowsWider() throws {
        var world = try world()
        try world.enableMapExpansion(owning: MapTile(row: 0, column: 0), townSeed: nil, ridersStep: 20_000)
        try world.buyMapTile(MapTile(row: 1, column: 0), passingMilestone: true)
        try world.buyMapTile(MapTile(row: 1, column: 1), passingMilestone: true)
        func tiles(_ world: GameWorld) -> [Int] { world.accounts.assets.filter { $0.kind == .mapTile }.map(\.owner) }
        XCTAssertEqual(tiles(world), [2, 3], "two tiles a row")
        try world.growMap(to: large)
        XCTAssertEqual(tiles(world), [4, 5], "four a row")
        XCTAssertEqual(world.mapExpansion?.owned, [MapTile(row: 0, column: 0), MapTile(row: 1, column: 0), MapTile(row: 1, column: 1)])
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world)), world, "a world GameCore loads")
    }

    // MARK: - Saves

    func testAPartTheAnchorIsTheMiddleOfMustFitTheWorld() throws {
        var world = try world()
        try world.growMap(to: large)
        let data = try JSONEncoder().encode(world)
        let saved = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        func load(_ change: (inout [String: Any]) -> Void) throws -> GameWorld {
            var changed = saved
            change(&changed)
            return try JSONDecoder().decode(GameWorld.self, from: JSONSerialization.data(withJSONObject: changed))
        }
        XCTAssertEqual(try load { _ in }, world)
        XCTAssertThrowsError(try load { $0["geoAnchor"] = nil }, "only a map over the Earth")
        XCTAssertThrowsError(try load { $0["geoAnchorBounds"] = ["width": 3_600_001, "height": 1_400_000] }, "wider than the world")
        XCTAssertThrowsError(try load { $0["geoAnchorBounds"] = ["width": 1_100_000, "height": 7_300_001] }, "longer than the world")
        XCTAssertThrowsError(try load { $0["geoAnchorBounds"] = ["width": 3_600_000, "height": 7_300_000] }, "the whole world is written as none")
    }

    /// The version 113 fixture: a city's map with a line running, grown to
    /// the next city, the company keeping its four tiles and buying a
    /// fifth. Written once, by the build that introduced the version
    /// (`MAP_GROWTH_SAVE_NEW`); every later build reads it to the same
    /// world and runs it on the same.
    func testTheVersion113FixtureLoadsToTheWorldThisBuildMakes() throws {
        var world = GameWorld(bounds: small, economy: fixtureEconomy(balance: 100_000_000_000, costs: testCosts), clock: GameClock(speed: .normal))
        world.setEconomyMode(.management)
        world.setGeoAnchor(anchor)
        world.setLandOnDemand()
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 500_000, y: 700_000))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 900_000, y: 700_000))
        let edge = try world.buildTrackEdge(from: a, to: b)
        let west = try world.buildStation(named: "West", at: PlanPoint(x: 520_000, y: 705_000)).id
        let east = try world.buildStation(named: "East", at: PlanPoint(x: 880_000, y: 705_000)).id
        try world.addTrackPlatform(west, on: edge, from: 10_000, to: 30_000)
        try world.addTrackPlatform(east, on: edge, from: 370_000, to: 390_000)
        try world.createLine(named: "Main", stops: [west, east])
        try world.expandLand(
            [LandBlock(row: 10, column: 7), LandBlock(row: 21, column: 16)], cells: [cell(165, 127, residents: 300), cell(337, 257, residents: 40)],
            water: [CellPosition(row: 161, column: 112), CellPosition(row: 336, column: 256)]
        )
        try world.advance(ticks: 3)
        try world.growMap(to: large)
        try world.enableMapExpansion(
            owning: [MapTile(row: 0, column: 0), MapTile(row: 0, column: 1), MapTile(row: 1, column: 0), MapTile(row: 1, column: 1)],
            townSeed: nil, ridersStep: 20_000
        )
        try world.buyMapTile(MapTile(row: 2, column: 0), passingMilestone: true)
        _ = try world.buildStation(named: "South", at: PlanPoint(x: 300_000, y: 2 * tile + 100_000))
        try world.advance(ticks: 3)

        let url = SavedGameTests.fixtures.appendingPathComponent("v113-grown-map.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["MAP_GROWTH_SAVE_NEW"] != nil, SavedGame.currentVersion == 113 {
            try encoder.encode(SavedGame(world: world)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 113)
        var loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(loaded.bounds, large)
        XCTAssertEqual(loaded.geoAnchorBounds, small)
        XCTAssertEqual(loaded.mapExpansion?.granted, 4)
        XCTAssertEqual(loaded.mapExpansion?.owned.count, 5)
        XCTAssertEqual(loaded.accounts.assets.filter { $0.kind == .mapTile }.map(\.owner), [8], "row 2 of four tiles a row")
        XCTAssertEqual(loaded.landBlocks, [LandBlock(row: 10, column: 7)])
        XCTAssertEqual(loaded, world, "the save is the world this build makes the same way")
        var running = world
        try loaded.advance(ticks: 600)
        try running.advance(ticks: 600)
        XCTAssertEqual(loaded, running)
    }
}
