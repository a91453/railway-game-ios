import Foundation
@testable import GameCore
import XCTest

/// Clearing the way (city building P0-C2, ARCHITECTURE decision 95): the
/// company's buildings buy out the city's buildings in their way, the city
/// puts nothing up where they stand, and track and stations built later
/// clear the company's buildings for what demolishing them costs. Every
/// number below is worked out by hand.
final class CompanyBuildingsClearingTests: XCTestCase {
    /// 32 × 24 cells.
    private static let small = try! WorldBounds(width: 131_072, height: 98_304)
    /// The middle of cell (5, 5): (22,528, 22,528).
    private static let middle = PlanPoint(x: 22_528, y: 22_528)

    /// A managed world with `balance`, no stations, and land of a D4 home
    /// on cell (5, 5) with 1,000 residents and 3 jobs, and shops on cell
    /// (5, 6) with 20 jobs, with the city's buildings on.
    private func world(balance: Money = 1_000_000_000, mode: EconomyMode = .management) throws -> GameWorld {
        var world = GameWorld(bounds: Self.small, economy: GameEconomy(balance: balance, costs: testCosts), clock: GameClock(speed: .paused))
        try world.setLand([
            LandCell(row: 5, column: 5, use: .residential, residents: 1_000, jobs: 3),
            LandCell(row: 5, column: 6, use: .commercial, residents: 0, jobs: 20),
        ])
        world.setCityBuildings(true)
        world.setEconomyMode(mode)
        return world
    }

    /// The world keeps its rules: it saves and reads back the same.
    private func assertSavesAndReads(_ world: GameWorld, line: UInt = #line) throws {
        let data = try JSONEncoder().encode(SavedGame(world: world))
        XCTAssertEqual(try JSONDecoder().decode(SavedGame.self, from: data).world, world, line: line)
    }

    // MARK: - Which city buildings a building claims

    func testABuildingClaimsTheCityBuildingsWhoseSquareItsGroundComesNear() throws {
        let world = try world()
        // A city building stands on the middle 2,560 units of its cell:
        // cell (5, 5)'s square runs from 20,480 + 768 = 21,248 to 23,808.
        func claimed(_ kind: PlacedBuildingKind, _ x: Int64, _ y: Int64) -> [CellPosition] {
            world.cityCells(claimedBy: PlacedBuilding(id: PlacedBuildingID(rawValue: 1), kind: kind, centre: PlanPoint(x: x, y: y))).map(\.position)
        }
        XCTAssertEqual(claimed(.office, 22_528, 22_528), [CellPosition(row: 5, column: 5)])
        // A house on the line between columns 4 and 5 (19,968 to 20,992,
        // 19,840 to 21,120 with the clearance) leaves both alone.
        XCTAssertEqual(claimed(.house, 20_480, 22_528), [])
        // 128 further east its grown square reaches 21,248: touching only.
        XCTAssertEqual(claimed(.house, 20_608, 22_528), [])
        XCTAssertEqual(claimed(.house, 20_609, 22_528), [CellPosition(row: 5, column: 5)])
        // An office (2,048 across) on the line between columns 5 and 6
        // claims both city buildings.
        XCTAssertEqual(claimed(.office, 24_576, 22_528), [CellPosition(row: 5, column: 5), CellPosition(row: 5, column: 6)])
        // No land, nothing to claim.
        XCTAssertEqual(claimed(.office, 60_000, 60_000), [])
    }

    // MARK: - Buying out

    func testBuildingOverACityBuildingBuysItOutAndItsPeopleMoveIn() throws {
        var world = try world()
        // The D4 home: 40 storeys of 1,536 m², 61,440 m² at 4,000 cents,
        // and its 1,600 m² square at the cell's land value, a fifth more.
        let home = try XCTUnwrap(world.land.cell(row: 5, column: 5))
        XCTAssertEqual(world.buildings.building(row: 5, column: 5)?.density, .d4)
        let value = try XCTUnwrap(world.landValue(row: 5, column: 5)?.value)
        // No station: the land is worth its D4 home's base, 4,000 a m².
        XCTAssertEqual(value, 4_000)
        // (245,760,000 + 6,400,000) × 120 / 100.
        XCTAssertEqual(world.buyOutPrice(of: home).amount, (61_440 * 4_000 + 1_600 * value) * 120 / 100)
        XCTAssertEqual(world.buyOutPrice(of: home), 302_592_000)
        let quote = try XCTUnwrap(world.placedBuildingQuote(.office, at: Self.middle))
        XCTAssertEqual(quote.cleared, [CellPosition(row: 5, column: 5)])
        XCTAssertEqual(quote.buyOut, world.buyOutPrice(of: home))
        // The office: 6,144 m² of floor, 24,576,000; 1,024 m² of land at
        // 4,000, 4,096,000.
        XCTAssertEqual([quote.building, quote.land], [24_576_000, 4_096_000])
        XCTAssertEqual(quote.total, 331_264_000)

        let balance = world.economy.balance
        let office = try world.placeBuilding(.office, at: Self.middle)
        XCTAssertEqual(world.economy.balance, balance - quote.total)
        XCTAssertEqual(office.landCost, quote.land + quote.buyOut, "the buy-out is part of what the land cost")
        XCTAssertEqual(world.accounts.assets.last?.cost, quote.total)
        // Its 1,000 residents and 3 jobs move in, up to the office's 16 and
        // 168: 16 and 3.
        XCTAssertEqual([office.residents, office.jobs], [16, 3])
        XCTAssertNil(world.land.cell(row: 5, column: 5), "the cell of land goes with its building")
        XCTAssertNil(world.buildings.building(row: 5, column: 5))
        XCTAssertNotNil(world.buildings.building(row: 5, column: 6), "the shops beside it stay, numbered as they were")
        try assertSavesAndReads(world)
    }

    func testABuyOutNeedsTheMoneyAndChangesNothingWithout() throws {
        var world = try world(balance: 100_000_000)
        let quote = try XCTUnwrap(world.placedBuildingQuote(.office, at: Self.middle))
        let before = world
        XCTAssertThrowsGameError(try world.placeBuilding(.office, at: Self.middle),
                                 .insufficientFunds(required: quote.total, available: 100_000_000))
        XCTAssertEqual(world, before)
    }

    func testFreePlayPullsTheCityBuildingDownForNothing() throws {
        var world = try world(mode: .free)
        let quote = try XCTUnwrap(world.placedBuildingQuote(.office, at: Self.middle))
        XCTAssertEqual(quote, PlacedBuildingQuote(building: .zero, land: .zero, cleared: [CellPosition(row: 5, column: 5)]))
        let office = try world.placeBuilding(.office, at: Self.middle)
        XCTAssertEqual(world.economy.balance, 1_000_000_000)
        XCTAssertEqual([office.residents, office.jobs], [16, 3])
        XCTAssertNil(world.land.cell(row: 5, column: 5))
    }

    // MARK: - The city keeps off

    func testTheCityPutsNothingUpWhereTheCompanysBuildingsStand() throws {
        var world = try world()
        // An office on the empty cell (6, 5), south of the home: it claims
        // that cell's building, though none stands there yet.
        try world.placeBuilding(.office, at: PlanPoint(x: 22_528, y: 26_624))
        XCTAssertTrue(world.isClaimedByPlacedBuilding(row: 6, column: 5))
        // A station on cell (7, 5): of the empty cells beside people, (6,
        // 5) is nearest (1 cell² away), but it is claimed, so the city
        // spreads to (6, 6), beside the shops (2 cells² away).
        let station = try world.buildStation(named: "S", at: PlanPoint(x: 22_528, y: 30_720))
        world.spread(towards: station)
        XCTAssertNil(world.land.cell(row: 6, column: 5))
        XCTAssertEqual(world.land.cells.count, 3)
        XCTAssertNotNil(world.land.cell(row: 6, column: 6))

        // Land set again keeps off it too.
        try world.setLand([LandCell(row: 6, column: 5, use: .residential, residents: 50, jobs: 0),
                           LandCell(row: 9, column: 9, use: .residential, residents: 50, jobs: 0)])
        XCTAssertEqual(world.land.cells.map(\.position), [CellPosition(row: 9, column: 9)])
        try assertSavesAndReads(world)
    }

    func testLandReadInLaterKeepsOffTheCompanysBuildings() throws {
        var world = try world()
        world.setLandOnDemand()
        try world.placeBuilding(.office, at: Self.middle)
        try world.expandLand([LandBlock(row: 0, column: 0)], cells: [
            LandCell(row: 5, column: 5, use: .residential, residents: 1_000, jobs: 0),
            LandCell(row: 5, column: 7, use: .residential, residents: 10, jobs: 0),
        ])
        XCTAssertEqual(world.land.cells.map(\.position), [CellPosition(row: 5, column: 7)])
        try assertSavesAndReads(world)
    }

    // MARK: - Track and stations clear the company's buildings

    /// A managed world with a house at (10,000, 10,000), its square 9,488
    /// to 10,512 each way, and two nodes either side of it on y = 10,000.
    private func trackWorld(balance: Money = 1_000_000_000, mode: EconomyMode = .management)
        throws -> (GameWorld, west: TrackNodeID, east: TrackNodeID, house: PlacedBuilding) {
        var world = GameWorld(bounds: Self.small, economy: GameEconomy(balance: balance, costs: testCosts), clock: GameClock(speed: .paused))
        world.setEconomyMode(mode)
        let house = try world.placeBuilding(.house, at: PlanPoint(x: 10_000, y: 10_000))
        let west = try world.buildTrackNode(at: WorldCoordinate(x: 4_000, y: 10_000))
        let east = try world.buildTrackNode(at: WorldCoordinate(x: 16_000, y: 10_000))
        return (world, west, east, house)
    }

    func testTrackThroughTheCompanysBuildingPullsItDownForItsFee() throws {
        var (world, west, east, house) = try trackWorld()
        // The house cost 2,048,000 + 256,000 (no land: the empty base, 1,000
        // a m²); demolishing it ⌈2,304,000 / 10⌉ = 230,400. The track is
        // 12,000 units, 12 lengths of 1,024 at 100.
        XCTAssertEqual(house.cost, 2_304_000)
        XCTAssertEqual(world.placedBuildings(inTheWayOf: [PlanPoint(x: 4_000, y: 10_000), PlanPoint(x: 16_000, y: 10_000)]), [house])
        let balance = world.economy.balance
        try world.buildTrackEdge(from: west, to: east)
        XCTAssertEqual(world.economy.balance, balance - 1_200 - 230_400)
        XCTAssertTrue(world.placedBuildings.isEmpty)
        XCTAssertFalse(world.accounts.assets.contains { $0.kind == .building })
        XCTAssertEqual(world.accounts.entries.last?.breakdown, [LedgerLine(item: .propertyDemolition, amount: -230_400)])
        XCTAssertEqual(world.financeReport(.day).current.netCashFlow, world.economy.balance - 1_000_000_000)
        try assertSavesAndReads(world)
    }

    func testTrackPassingAClearanceAwayLeavesItStanding() throws {
        var (world, _, _, house) = try trackWorld()
        // y = 10,512 + 128 = 10,640 is a whole clearance south of it.
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 4_000, y: 10_640))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 16_000, y: 10_640))
        try world.buildTrackEdge(from: a, to: b)
        XCTAssertEqual(world.placedBuildings, [house])
        // One unit nearer, it comes down.
        var nearer = try trackWorld().0
        let c = try nearer.buildTrackNode(at: WorldCoordinate(x: 4_000, y: 10_639))
        let d = try nearer.buildTrackNode(at: WorldCoordinate(x: 16_000, y: 10_639))
        try nearer.buildTrackEdge(from: c, to: d)
        XCTAssertTrue(nearer.placedBuildings.isEmpty)
    }

    func testATunnelPassesUnderTheCompanysBuildings() throws {
        var (world, _, _, house) = try trackWorld()
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 4_000, y: 10_000, z: -1_024))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 16_000, y: 10_000, z: -1_024))
        try world.buildTrackEdge(from: a, to: b, structure: .tunnel)
        XCTAssertEqual(world.placedBuildings, [house])
        // And a building may stand over a tunnel.
        XCTAssertNoThrow(try world.placeBuilding(.house, at: PlanPoint(x: 13_000, y: 10_000)))
    }

    func testClearingNeedsTheMoneyForTrackAndFeeTogether() throws {
        var (world, west, east, _) = try trackWorld(balance: 2_304_000 + 100_000)
        let before = world
        XCTAssertThrowsGameError(try world.buildTrackEdge(from: west, to: east),
                                 .insufficientFunds(required: 1_200 + 230_400, available: 100_000))
        XCTAssertEqual(world, before)
    }

    func testAStationAtTheCompanysBuildingPullsItDown() throws {
        var (world, _, _, house) = try trackWorld()
        // 10,640 is a clearance from it; 10,639 is within.
        try world.buildStation(named: "Clear", at: PlanPoint(x: 10_000, y: 10_640))
        XCTAssertEqual(world.placedBuildings, [house])
        let balance = world.economy.balance
        try world.buildStation(named: "Here", at: PlanPoint(x: 10_000, y: 10_639))
        XCTAssertTrue(world.placedBuildings.isEmpty)
        XCTAssertEqual(world.economy.balance, balance - 1_000 - 230_400)
        try assertSavesAndReads(world)
    }

    func testFreePlayClearsTheWayForNothing() throws {
        var (world, west, east, _) = try trackWorld(mode: .free)
        try world.buildTrackEdge(from: west, to: east)
        XCTAssertTrue(world.placedBuildings.isEmpty)
        XCTAssertEqual(world.economy.balance, 1_000_000_000 - 1_200)
        XCTAssertTrue(world.accounts.entries.isEmpty)
    }
}
