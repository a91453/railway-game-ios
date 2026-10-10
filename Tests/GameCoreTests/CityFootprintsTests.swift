import Foundation
@testable import GameCore
import XCTest

/// The city's footprints (ARCHITECTURE decision 142): with them on, a city
/// building stands on a square of its density's size, 20 m for D1 to 40 m
/// for D4, rather than 40 m whatever its height (decision 95), so a low
/// town leaves room for the company's buildings between its own. A
/// building claims, buys out and keeps the city from growing by those
/// squares, and a city building is not raised into a company building.
final class CityFootprintsTests: XCTestCase {
    /// 32 × 24 cells.
    private static let small = try! WorldBounds(width: 131_072, height: 98_304)
    /// Beside the D1 home on cell (5, 5): its 20 m square runs from 20,480
    /// + 1,408 = 21,888 to 23,168, so an office (2,048 across) centred
    /// 1,024 + 128 east of it touches it with the clearance only.
    private static let besideTheHome = PlanPoint(x: 24_320, y: 22_528)

    /// A managed world with no stations, a D1 home of 4 residents on cell
    /// (5, 5) and a D4 home of 1,000 on cell (5, 9), with the city's
    /// buildings on, and the footprints as `footprints`.
    private func world(footprints: Bool) throws -> GameWorld {
        var world = GameWorld(bounds: Self.small, economy: GameEconomy(balance: 1_000_000_000, costs: testCosts), clock: GameClock(speed: .paused))
        try world.setLand([
            LandCell(row: 5, column: 5, use: .residential, residents: 4, jobs: 0),
            LandCell(row: 5, column: 9, use: .residential, residents: 1_000, jobs: 3),
        ])
        world.setCityBuildings(true)
        world.setEconomyMode(.management)
        world.setCityFootprints(footprints)
        return world
    }

    func testASquareIsItsDensitysWithTheFootprintsAndFortyMetresWithout() throws {
        XCTAssertEqual(BuildingDensity.allCases.map(PlacedBuildingRules.cityBuildingSide(of:)), [1_280, 1_792, 2_176, 2_560])
        XCTAssertEqual(PlacedBuildingRules.cityBuildingSide(of: .d4), PlacedBuildingRules.cityBuildingSide)

        let on = try world(footprints: true), off = try world(footprints: false)
        XCTAssertEqual(on.buildings.building(row: 5, column: 5)?.density, .d1)
        XCTAssertEqual(on.buildings.building(row: 5, column: 9)?.density, .d4)
        XCTAssertEqual(on.cityBuildingSide(row: 5, column: 5), 1_280)
        XCTAssertEqual(on.cityBuildingSide(row: 5, column: 9), 2_560)
        XCTAssertEqual(on.cityBuildingSide(row: 0, column: 0), 1_280, "where the city would grow, a D1's")
        for (row, column) in [(5, 5), (5, 9), (0, 0)] {
            XCTAssertEqual(off.cityBuildingSide(row: row, column: column), 2_560)
        }
    }

    /// An office beside a D1 home leaves it standing with the footprints;
    /// without them its 40 m square is in the way and is bought out.
    func testAnOfficeFitsBesideALowHomeWithTheFootprints() throws {
        var on = try world(footprints: true)
        XCTAssertEqual(on.placedBuildingQuote(.office, at: Self.besideTheHome)?.cleared, [])
        // One unit further west, it reaches the home's square.
        XCTAssertEqual(on.placedBuildingQuote(.office, at: PlanPoint(x: 24_319, y: 22_528))?.cleared, [CellPosition(row: 5, column: 5)])
        _ = try on.placeBuilding(.office, at: Self.besideTheHome)
        XCTAssertNotNil(on.land.cell(row: 5, column: 5))
        XCTAssertNotNil(on.buildings.building(row: 5, column: 5))

        var off = try world(footprints: false)
        XCTAssertEqual(off.placedBuildingQuote(.office, at: Self.besideTheHome)?.cleared, [CellPosition(row: 5, column: 5)])
        _ = try off.placeBuilding(.office, at: Self.besideTheHome)
        XCTAssertNil(off.land.cell(row: 5, column: 5))
    }

    /// The buy-out pays for the land of the smaller square; a D4's is the
    /// same with or without the footprints.
    func testABuyOutPaysForTheSquareTheBuildingStandsOn() throws {
        let on = try world(footprints: true), off = try world(footprints: false)
        let home = try XCTUnwrap(on.land.cell(row: 5, column: 5)), tower = try XCTUnwrap(on.land.cell(row: 5, column: 9))
        let value = try XCTUnwrap(on.landValue(row: 5, column: 5)).value
        XCTAssertEqual(try XCTUnwrap(off.landValue(row: 5, column: 5)).value, value)
        // Two storeys of 1,536 m² at $40, and 20 × 20 m (40 × 40 m) of land,
        // a fifth more.
        let floor: Int64 = 2 * 1_536 * 4_000
        XCTAssertEqual(on.buyOutPrice(of: home), Money((floor + 400 * value) * 120 / 100))
        XCTAssertEqual(off.buyOutPrice(of: home), Money((floor + 1_600 * value) * 120 / 100))
        XCTAssertLessThan(on.buyOutPrice(of: home), off.buyOutPrice(of: home))
        XCTAssertEqual(on.buyOutPrice(of: tower), off.buyOutPrice(of: tower))
    }

    /// A city building whose next density's square would reach a company
    /// building is not raised; one with room is.
    func testACityBuildingIsNotRaisedIntoACompanyBuilding() throws {
        var world = try world(footprints: true)
        _ = try world.placeBuilding(.office, at: Self.besideTheHome)
        // D2's 28 m square would run to 20,480 + 1,152 + 1,792 = 23,424,
        // past the office's 23,296 − 128.
        XCTAssertTrue(world.raiseIsBlocked(at: CellPosition(row: 5, column: 5)))
        XCTAssertFalse(world.raiseIsBlocked(at: CellPosition(row: 5, column: 9)), "D4 is not raised")

        let station = try world.buildStation(named: "S", at: PlanPoint(x: 22_528, y: 26_000))
        var raised: Set<CellPosition> = []
        world.raiseBuildings(around: station, full: [CellPosition(row: 5, column: 5)], raised: &raised)
        XCTAssertEqual(raised, [])
        XCTAssertEqual(world.buildings.building(row: 5, column: 5)?.density, .d1)

        // Without the company building it is raised.
        var free = try self.world(footprints: true)
        let other = try free.buildStation(named: "S", at: PlanPoint(x: 22_528, y: 26_000))
        XCTAssertFalse(free.raiseIsBlocked(at: CellPosition(row: 5, column: 5)))
        free.raiseBuildings(around: other, full: [CellPosition(row: 5, column: 5)], raised: &raised)
        XCTAssertEqual(free.buildings.building(row: 5, column: 5)?.density, .d2)
    }

    /// The city grows no new cell whose D1 square a company building
    /// reaches, and grows one beside it whose square it does not.
    func testNewLandKeepsClearOfTheCompanysBuildings() throws {
        var world = try world(footprints: true)
        _ = try world.placeBuilding(.office, at: Self.besideTheHome)
        // The office runs from 23,296 to 25,344 across columns 5 and 6:
        // cell (5, 6)'s D1 square starts at 24,576 + 1,408 = 25,984,
        // beyond 25,344 + 128; without the footprints its 40 m square
        // starts at 25,344, within the clearance.
        XCTAssertFalse(world.isClaimedByPlacedBuilding(row: 5, column: 6))
        world.setCityFootprints(false)
        XCTAssertTrue(world.isClaimedByPlacedBuilding(row: 5, column: 6))
    }

    /// A sold building's people move to a cell the city may build on: one
    /// no other company building claims by the square of the building the
    /// city then puts up there, which may be denser than the cell's now
    /// (decision 130 with decision 142).
    func testASoldBuildingsPeopleDoNotMoveIntoAnotherBuildingsSquare() throws {
        var world = GameWorld(bounds: Self.small, economy: GameEconomy(balance: 1_000_000_000, costs: testCosts), clock: GameClock(speed: .paused))
        try world.setLand([LandCell(row: 5, column: 5, use: .office, residents: 0, jobs: 150)])
        world.setCityBuildings(true)
        world.setEconomyMode(.management)
        world.setCityFootprints(true)
        XCTAssertEqual(world.buildings.building(row: 5, column: 5)?.density, .d2)
        let office = try world.placeBuilding(.office, at: PlanPoint(x: 21_580, y: 22_528))
        XCTAssertNil(world.land.cell(row: 5, column: 5), "the office took the cell's jobs in")
        // Beside the cell: clear of a D1's square there, not of a D2's.
        let house = try world.placeBuilding(.house, at: PlanPoint(x: 23_812, y: 22_528))
        XCTAssertFalse(CityBuildingsClaim.claims(house, side: PlacedBuildingRules.cityBuildingSide(of: .d1)))
        XCTAssertTrue(CityBuildingsClaim.claims(house, side: PlacedBuildingRules.cityBuildingSide(of: .d2)))

        _ = try world.sellPlacedBuilding(office.id)
        for cell in world.land.cells {
            XCTAssertFalse(world.isClaimedByPlacedBuilding(row: cell.row, column: cell.column),
                           "the house claims the city's building on (\(cell.row), \(cell.column))")
        }
        XCTAssertNotNil(world.placedBuildings.first { $0.id == house.id })
    }

    /// With the city's buildings off no city building stands on the cell
    /// to stay, so a sold building's people are judged by the square the
    /// city would put up for them once they have moved in, not by the
    /// cell's now: here 20 jobs are a D1 square the house beside it clears,
    /// and 150 a D2 square it does not.
    func testASoldBuildingsPeopleKeepClearWithTheCitysBuildingsOff() throws {
        var world = GameWorld(bounds: Self.small, economy: GameEconomy(balance: 1_000_000_000, costs: testCosts), clock: GameClock(speed: .paused))
        try world.setLand([LandCell(row: 5, column: 5, use: .office, residents: 0, jobs: 20)])
        world.setEconomyMode(.management)
        world.setCityFootprints(true)
        XCTAssertFalse(world.cityBuildings)
        let house = try world.placeBuilding(.house, at: PlanPoint(x: 23_812, y: 22_528))
        XCTAssertFalse(world.isClaimedByPlacedBuilding(row: 5, column: 5))
        XCTAssertTrue(CityBuildingsClaim.claims(house, side: PlacedBuildingRules.cityBuildingSide(of: .d2)))
        // An office being sold whose centre lies in the cell: its 130 jobs
        // make the cell's 150.
        var office = PlacedBuilding(id: PlacedBuildingID(rawValue: 99), kind: .office, centre: PlanPoint(x: 21_580, y: 22_528))
        office.jobs = 130
        XCTAssertNotEqual(world.handOverCell(of: office), CellPosition(row: 5, column: 5))
    }

    func testTheFootprintsAreSavedOnlyWhenOn() throws {
        let off = try world(footprints: false)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(off), as: UTF8.self).contains("cityFootprints"))
        let on = try world(footprints: true)
        let data = try JSONEncoder().encode(on)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains(#""cityFootprints":true"#))
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: data), on)
        XCTAssertTrue(try JSONDecoder().decode(GameWorld.self, from: data).cityFootprints)
    }

    /// Version 33 (decision 142): `world(footprints: true)` with an office
    /// beside the D1 home, run ten minutes. It saves byte for byte and is
    /// the world this build makes.
    func testVersionThirtyThreeKeepsTheCitysFootprints() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SaveFixtures/v33-city-footprints.json")
        var made = try world(footprints: true)
        _ = try made.placeBuilding(.office, at: Self.besideTheHome)
        made.setSpeed(.normal)
        try made.advance(ticks: 10)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["CITY_FOOTPRINTS_SAVE_NEW"] != nil {
            try encoder.encode(SavedGame(world: made)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 33)
        let world = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(world, made)
        XCTAssertTrue(world.cityFootprints)
        XCTAssertNotNil(world.land.cell(row: 5, column: 5))
        XCTAssertEqual(try encoder.encode(SavedGame(world: world)), Data(String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #""saveVersion" : 33,"#, with: #""saveVersion" : \#(SavedGame.currentVersion),"#).utf8))
    }
}

/// Whether a company building claims cell (5, 5)'s city building of a
/// square `side` across.
private enum CityBuildingsClaim {
    static func claims(_ building: PlacedBuilding, side: Int64) -> Bool {
        GameWorld.claims(building, row: 5, column: 5, side: side)
    }
}
