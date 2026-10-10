import Foundation
@testable import GameCore
import XCTest

/// Buying out by area (ARCHITECTURE decision 146): with it on, a company
/// building buys out the share of each cell of land it covers, rather than
/// the city buildings whose squares it reaches (decisions 95 and 142); that
/// share of the cell's people move in, the cell and its building stay, and
/// the cell grows to its limits less the share the company covers.
final class AreaBuyOutTests: XCTestCase {
    /// 32 × 24 cells.
    private static let small = try! WorldBounds(width: 131_072, height: 98_304)
    /// An office on the line between cells (5, 5) and (5, 6): an eighth of
    /// each (1,024 × 2,048 units).
    private static let betweenTheHomes = PlanPoint(x: 24_576, y: 22_528)
    /// A house wholly in cell (5, 5), at its west edge: a sixteenth of it.
    private static let inTheWestHome = PlanPoint(x: 20_992, y: 22_528)
    /// An eighth of a cell, in square world units.
    private static let eighth = Land.cellArea / 8

    /// A managed world with no stations, D1 homes of 48 residents and 8
    /// jobs on cells (5, 5) and (5, 6), the city's buildings and footprints
    /// on, and buying out by area as `area`.
    private func world(area: Bool) throws -> GameWorld {
        var world = GameWorld(bounds: Self.small, economy: GameEconomy(balance: 1_000_000_000, costs: testCosts), clock: GameClock(speed: .paused))
        try world.setLand([
            LandCell(row: 5, column: 5, use: .residential, residents: 48, jobs: 8),
            LandCell(row: 5, column: 6, use: .residential, residents: 48, jobs: 8),
        ])
        world.setCityBuildings(true)
        world.setEconomyMode(.management)
        world.setCityFootprints(true)
        world.setAreaBuyOut(area)
        return world
    }

    private func office(at centre: PlanPoint) -> PlacedBuilding {
        PlacedBuilding(id: PlacedBuildingID(rawValue: 1), kind: .office, centre: centre)
    }

    func testAShareIsTheGroundTheSquareCoversOfEachCell() throws {
        let world = try world(area: true)
        let shares = world.cityShares(coveredBy: office(at: Self.betweenTheHomes))
        XCTAssertEqual(shares.map(\.cell.position), [CellPosition(row: 5, column: 5), CellPosition(row: 5, column: 6)])
        XCTAssertEqual(shares.map(\.area), [Self.eighth, Self.eighth])
        // A cell with no land is not listed, however much it covers.
        XCTAssertEqual(world.cityShares(coveredBy: office(at: PlanPoint(x: 2_048, y: 2_048))).count, 0)
        // Touching a cell's edge covers none of it.
        let house = PlacedBuilding(id: PlacedBuildingID(rawValue: 1), kind: .house, centre: PlanPoint(x: 24_576 - 512, y: 22_528))
        XCTAssertEqual(world.cityShares(coveredBy: house).map(\.cell.position), [CellPosition(row: 5, column: 5)])
    }

    /// The office pays an eighth of each home's buy-out and pulls nothing
    /// down; by squares it stands between the homes' 20 m squares and buys
    /// out neither.
    func testTheQuotePaysTheShareOfEachCellAndClearsNothing() throws {
        let on = try world(area: true), off = try world(area: false)
        let home = try XCTUnwrap(on.land.cell(row: 5, column: 5))
        XCTAssertEqual(on.buyOutPrice(of: home), 15_705_600)
        let quote = try XCTUnwrap(on.placedBuildingQuote(.office, at: Self.betweenTheHomes))
        XCTAssertEqual(quote.cleared, [])
        XCTAssertEqual(quote.buyOut, Money(2 * 15_705_600 / 8))
        XCTAssertEqual(quote.building, 24_576_000)
        XCTAssertEqual(quote.land, 2_048_000)
        // By squares the office reaches neither home's 20 m square in the
        // middle of its cell, and pays nothing for the city's buildings.
        let bySquares = try XCTUnwrap(off.placedBuildingQuote(.office, at: Self.betweenTheHomes))
        XCTAssertEqual(bySquares.cleared, [])
        XCTAssertEqual(bySquares.buyOut, .zero)
        // On a home's square, by squares it pays the whole and pulls it down;
        // by area a sixteenth.
        let middle = PlanPoint(x: 22_528, y: 22_528)
        XCTAssertEqual(off.placedBuildingQuote(.house, at: middle)?.cleared, [CellPosition(row: 5, column: 5)])
        XCTAssertEqual(off.placedBuildingQuote(.house, at: middle)?.buyOut, 15_705_600)
        XCTAssertEqual(on.placedBuildingQuote(.house, at: middle)?.cleared, [])
        XCTAssertEqual(on.placedBuildingQuote(.house, at: middle)?.buyOut, Money(15_705_600 / 16))
    }

    func testFreePlayPaysNothingForTheShares() throws {
        var world = try world(area: true)
        world.setEconomyMode(.free)
        let quote = try XCTUnwrap(world.placedBuildingQuote(.office, at: Self.betweenTheHomes))
        XCTAssertEqual(quote.total, .zero)
        XCTAssertEqual(quote.cleared, [])
    }

    /// Placing moves the shares' people in and leaves both cells and their
    /// buildings standing.
    func testPlacingMovesTheSharesPeopleInAndKeepsTheCells() throws {
        var world = try world(area: true)
        let building = try world.placeBuilding(.office, at: Self.betweenTheHomes)
        XCTAssertEqual(building.residents, 12)
        XCTAssertEqual(building.jobs, 2)
        XCTAssertEqual(building.landCost, Money(2_048_000 + 2 * 15_705_600 / 8))
        for column in [5, 6] {
            XCTAssertEqual(world.land.cell(row: 5, column: column), LandCell(row: 5, column: column, use: .residential, residents: 42, jobs: 7))
            XCTAssertEqual(world.buildings.building(row: 5, column: column)?.density, .d1)
        }
        // A share's people are rounded down: a sixteenth of 42 and 7.
        let house = try world.placeBuilding(.house, at: Self.inTheWestHome)
        XCTAssertEqual(house.residents, 2)
        XCTAssertEqual(house.jobs, 0)
        XCTAssertEqual(world.land.cell(row: 5, column: 5)?.residents, 40)
        XCTAssertEqual(world.land.cell(row: 5, column: 5)?.jobs, 7)
    }

    /// The cells under the company's buildings grow to their limits less
    /// what the buildings cover; the others to their whole.
    func testACellsLimitsLeaveOutWhatTheCompanyCovers() throws {
        var world = try world(area: true)
        let home = try XCTUnwrap(world.land.cell(row: 5, column: 5))
        // A D1 home holds 56 residents and its cell's 8 jobs (12 by the
        // table).
        XCTAssertEqual(world.growthLimits(of: home).residents, 56)
        XCTAssertEqual(world.growthLimits(of: home).jobs, 12)
        _ = try world.placeBuilding(.office, at: Self.betweenTheHomes)
        let after = try XCTUnwrap(world.land.cell(row: 5, column: 5))
        XCTAssertEqual(world.coveredArea(row: 5, column: 5), Self.eighth)
        XCTAssertEqual(world.growthLimits(of: after).residents, 56 * 7 / 8)
        XCTAssertEqual(world.growthLimits(of: after).jobs, 12 * 7 / 8)
        XCTAssertEqual(world.coveredAreas(), [CellPosition(row: 5, column: 5): Self.eighth, CellPosition(row: 5, column: 6): Self.eighth])

        // By squares the limits are the building's whole.
        var off = try self.world(area: false)
        _ = try off.placeBuilding(.office, at: Self.betweenTheHomes)
        XCTAssertEqual(off.growthLimits(of: try XCTUnwrap(off.land.cell(row: 5, column: 5))).residents, 56)
    }

    /// A building's squares do not hold the city back: no raise is blocked,
    /// and only a cell the company covers whole keeps new land off.
    func testNoRaiseIsBlockedAndOnlyAWholeCellIsClaimed() throws {
        var world = try world(area: true)
        _ = try world.placeBuilding(.office, at: Self.betweenTheHomes)
        XCTAssertFalse(world.raiseIsBlocked(at: CellPosition(row: 5, column: 5)))
        XCTAssertFalse(world.isClaimedByPlacedBuilding(row: 5, column: 5))
        XCTAssertFalse(world.isClaimedByPlacedBuilding(row: 5, column: 6))

        // By squares, a house beside the D1 square blocks its raise.
        var off = try self.world(area: false)
        _ = try off.placeBuilding(.house, at: PlanPoint(x: 21_888 - 128 - 512, y: 22_528))
        XCTAssertTrue(off.raiseIsBlocked(at: CellPosition(row: 5, column: 5)))
    }

    /// A share of a large price is worked out without overflow, and equals
    /// the share worked out in one step where that fits.
    func testAShareOfAPriceIsRoundedDownAndDoesNotOverflow() throws {
        var world = try world(area: true)
        world.setCityBuildings(false)
        let home = try XCTUnwrap(world.land.cell(row: 5, column: 5))
        let whole = world.buyOutPrice(of: home).amount
        for covered in [1, 1_000, Self.eighth, Land.cellArea - 1] {
            XCTAssertEqual(world.buyOutPrice(of: home, covered: covered).amount, whole * covered / Land.cellArea)
        }
        XCTAssertEqual(world.buyOutPrice(of: home, covered: Land.cellArea).amount, whole)
    }

    func testBuyingOutByAreaIsSavedOnlyWhenOn() throws {
        let off = try world(area: false)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(off), as: UTF8.self).contains("areaBuyOut"))
        let on = try world(area: true)
        let data = try JSONEncoder().encode(on)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains(#""areaBuyOut":true"#))
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: data), on)
    }

    /// Version 34 (decision 146): `world(area: true)` with the office
    /// between the homes, run ten minutes. It saves byte for byte and is
    /// the world this build makes.
    func testVersionThirtyFourKeepsBuyingOutByArea() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SaveFixtures/v34-area-buyout.json")
        var made = try world(area: true)
        _ = try made.placeBuilding(.office, at: Self.betweenTheHomes)
        made.setSpeed(.normal)
        try made.advance(ticks: 10)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["AREA_BUYOUT_SAVE_NEW"] != nil {
            try encoder.encode(SavedGame(world: made)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 34)
        let world = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(world, made)
        XCTAssertTrue(world.areaBuyOut)
        XCTAssertEqual(world.land.cell(row: 5, column: 5)?.residents, 42)
        XCTAssertEqual(try encoder.encode(SavedGame(world: world)), Data(String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #""saveVersion" : 34,"#, with: #""saveVersion" : \#(SavedGame.currentVersion),"#).utf8))
    }
}
