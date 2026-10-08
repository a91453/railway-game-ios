import Foundation
@testable import GameCore
import XCTest

/// Zoning (city building P0-B, ARCHITECTURE decision 98): a layer of zones
/// per cell that the city's growth follows, two zones that keep it off, and
/// the company's buildings making the zoned cells near them worth more.
/// Every number below is worked out by hand.
final class ZoningTests: XCTestCase {
    /// 32 × 24 cells.
    private static let small = try! WorldBounds(width: 131_072, height: 98_304)
    /// Station S0 stands at the middle of cell (5, 5), where 1,000 people
    /// live.
    private static let stationPoint = PlanPoint(x: 22_528, y: 22_528)

    /// A managed world whose land sets ridership with town growth on, the
    /// station measured at 800 and 2 stations reached.
    private func world(land: [LandCell] = [LandCell(row: 5, column: 5, use: .residential, residents: 1_000, jobs: 0)]) throws -> GameWorld {
        var world = GameWorld(bounds: Self.small, economy: GameEconomy(balance: 1_000_000_000, costs: testCosts), clock: GameClock(speed: .normal))
        try world.setLand(land)
        world.setEconomyMode(.management)
        world.setLandDemand(true)
        world.setTownGrowth(true)
        try world.buildStation(named: "S0", at: Self.stationPoint)
        world.growLand(reached: [:])
        world.townGrowth!.places[0].lastService = 800
        world.townGrowth!.places[0].lastReached = 2
        return world
    }

    private func station(of world: GameWorld) -> Station {
        world.stations[0]
    }

    // MARK: - The command

    func testZoningARectangleCountsTheCellsThatChange() throws {
        var world = try world()
        XCTAssertTrue(world.zones.isEmpty)
        XCTAssertEqual(try world.setZone(.commercial, rows: 0...1, columns: 0...2), 6)
        XCTAssertEqual(try world.setZone(.commercial, rows: 0...1, columns: 0...2), 0, "already so")
        XCTAssertEqual(try world.setZone(.office, rows: 1...2, columns: 2...2), 2)
        XCTAssertEqual(try world.setZone(nil, rows: 0...0, columns: 0...0), 1)
        XCTAssertEqual(try world.setZone(nil, rows: 0...0, columns: 0...0), 0)
        XCTAssertEqual(world.zones.cells, [
            ZonedCell(row: 0, column: 1, zone: .commercial), ZonedCell(row: 0, column: 2, zone: .commercial),
            ZonedCell(row: 1, column: 0, zone: .commercial), ZonedCell(row: 1, column: 1, zone: .commercial),
            ZonedCell(row: 1, column: 2, zone: .office), ZonedCell(row: 2, column: 2, zone: .office),
        ])
        XCTAssertEqual(world.zones.zone(row: 1, column: 2), .office)
        XCTAssertNil(world.zones.zone(row: 0, column: 0))
        // Zoning is free and changes no land.
        XCTAssertEqual(world.economy.balance, 1_000_000_000 - testCosts.station)
        XCTAssertEqual(world.land.cells.count, 1)
    }

    func testARectangleOutsideTheWorldOrTooLargeIsRefused() throws {
        var world = try world()
        let before = world
        for (rows, columns) in [(-1...0, 0...0), (0...0, -1...0), (23...24, 0...0), (0...0, 31...32)] {
            XCTAssertThrowsError(try world.setZone(.residential, rows: rows, columns: columns)) {
                XCTAssertEqual($0 as? GameError, .invalidZoneArea)
            }
        }
        XCTAssertEqual(world, before)
        // 200 cells a side: 128 is the most a side.
        var large = GameWorld(bounds: try WorldBounds(width: 819_200, height: 819_200), economy: GameEconomy(balance: 0, costs: testCosts))
        XCTAssertEqual(try large.setZone(.reserved, rows: 0...127, columns: 72...199), 16_384)
        XCTAssertThrowsError(try large.setZone(.reserved, rows: 0...128, columns: 0...0))
        XCTAssertThrowsError(try large.setZone(nil, rows: 0...0, columns: 0...128))
    }

    // MARK: - Growth

    func testWithoutZonesTheTownSpreadsAsBefore() throws {
        var world = try world()
        world.spread(towards: station(of: world))
        // The four cells beside (5, 5) are equally near: by row, (4, 5).
        XCTAssertEqual(world.land.cell(row: 4, column: 5), LandCell(row: 4, column: 5, use: .residential, residents: 4, jobs: 0))
        XCTAssertEqual(world.land.cells.count, 2)
    }

    func testZonesElsewhereLeaveTheTownAsBefore() throws {
        var world = try world()
        // (20, 30) is far outside S0's 800 m, and (5, 5) already has land.
        try world.setZone(.commercial, rows: 20...20, columns: 30...30)
        try world.setZone(.office, rows: 5...5, columns: 5...5)
        world.spread(towards: station(of: world))
        XCTAssertEqual(world.land.cell(row: 4, column: 5)?.residents, 4)
        XCTAssertEqual(world.land.cell(row: 5, column: 5)?.use, .residential, "land already there keeps its use")
    }

    func testTheTownSpreadsOntoTheZonedCellWorthMost() throws {
        var world = try world()
        try world.setZone(.commercial, rows: 10...10, columns: 5...6)
        // (10, 5)'s middle is 20,480 south of S0: w = 1000 − ⌊20480² × 1000
        // / 51200²⌋ = 840, S = 840 × 800 / 1000 = 672; (10, 6)'s is 4,096
        // east of that too: ⌊436,207,616,000 / 2,621,440,000⌋ = 166, w =
        // 834, S = 667. Empty land (1,000), access 2 × 1,000.
        XCTAssertEqual(world.landValue(row: 10, column: 5)?.value, 1_000 + 15 * 672 + 2_000)
        XCTAssertEqual(world.landValue(row: 10, column: 6)?.value, 1_000 + 15 * 667 + 2_000)
        world.spread(towards: station(of: world))
        // Shops: a quarter of 4 living there and three times 4 working.
        XCTAssertEqual(world.land.cell(row: 10, column: 5), LandCell(row: 10, column: 5, use: .commercial, residents: 1, jobs: 12))
        XCTAssertNil(world.land.cell(row: 4, column: 5), "a zoned cell is built on first, beside people or not")
        world.spread(towards: station(of: world))
        XCTAssertEqual(world.land.cell(row: 10, column: 6)?.use, .commercial)
        // No zoned cell is left empty: the town spreads as before.
        world.spread(towards: station(of: world))
        XCTAssertEqual(world.land.cell(row: 4, column: 5)?.use, .residential)
    }

    func testEachZoneBuildsItsUse() throws {
        let expected: [Zone: LandCell] = [
            .residential: LandCell(row: 10, column: 5, use: .residential, residents: 4, jobs: 0),
            .commercial: LandCell(row: 10, column: 5, use: .commercial, residents: 1, jobs: 12),
            .office: LandCell(row: 10, column: 5, use: .office, residents: 1, jobs: 12),
            .industrial: LandCell(row: 10, column: 5, use: .industrial, residents: 0, jobs: 8),
            .civic: LandCell(row: 10, column: 5, use: .civic, residents: 1, jobs: 4),
            .leisure: LandCell(row: 10, column: 5, use: .leisure, residents: 0, jobs: 4),
        ]
        for zone in Zone.allCases {
            var world = try world()
            try world.setZone(zone, rows: 10...10, columns: 5...5)
            world.spread(towards: station(of: world))
            XCTAssertEqual(world.land.cell(row: 10, column: 5), expected[zone], "\(zone)")
        }
    }

    func testTheCompanysBuildingsLeadTheTownsSpread() throws {
        var world = try world()
        try world.setZone(.residential, rows: 10...10, columns: 0...0)
        try world.setZone(.residential, rows: 10...10, columns: 10...10)
        // Both middles are 20,480 east or west and 20,480 south of S0:
        // ⌊838,860,800,000 / 2,621,440,000⌋ = 320, w = 680, S = 544, worth
        // 1,000 + 15 × 544 + 2,000 = 11,160. A tie goes to the lower column.
        XCTAssertEqual(world.landValue(row: 10, column: 0)?.value, 11_160)
        XCTAssertEqual(world.landValue(row: 10, column: 10)?.value, 11_160)
        var plain = world
        plain.spread(towards: station(of: plain))
        XCTAssertNotNil(plain.land.cell(row: 10, column: 0))

        // A house centred on (10, 12)'s middle (51,200, 43,008) is 8,192
        // from (10, 10)'s and 49,152 from (10, 0)'s: only the first lies
        // within 400 m (25,600).
        try world.placeBuilding(.house, at: PlanPoint(x: 51_200, y: 43_008))
        XCTAssertEqual(world.landValue(row: 10, column: 10)?.companyPremium, 600)
        XCTAssertEqual(world.landValue(row: 10, column: 10)?.value, 11_760)
        XCTAssertEqual(world.landValue(row: 10, column: 0)?.companyPremium, 0)
        world.spread(towards: station(of: world))
        XCTAssertNotNil(world.land.cell(row: 10, column: 10))
        XCTAssertNil(world.land.cell(row: 10, column: 0))
    }

    func testOnlyZonedCellsNearTheCompanysBuildingsAreWorthMore() throws {
        var world = try world()
        try world.placeBuilding(.house, at: PlanPoint(x: 51_200, y: 43_008))
        // Without zones nothing is: a world before decision 98 is worth what
        // it was.
        XCTAssertEqual(world.landValue(row: 10, column: 12)?.companyPremium, 0)
        try world.setZone(.noDevelopment, rows: 10...10, columns: 11...11)
        try world.setZone(.reserved, rows: 10...10, columns: 13...13)
        try world.setZone(.office, rows: 10...10, columns: 12...12)
        XCTAssertEqual(world.landValue(row: 10, column: 12)?.companyPremium, 600, "its own cell too")
        XCTAssertEqual(world.landValue(row: 10, column: 11)?.companyPremium, 0, "no development is not zoned for a use")
        XCTAssertEqual(world.landValue(row: 10, column: 13)?.companyPremium, 0)
        XCTAssertEqual(world.landValue(row: 11, column: 12)?.companyPremium, 0, "not zoned")
        // The premium is worked out the same, cell by cell or together.
        XCTAssertEqual(world.landValues(rows: 10...10, columns: 12...12), [world.landValue(row: 10, column: 12)!])
        XCTAssertEqual(world.landValues(at: [CellPosition(row: 10, column: 12)]), [world.landValue(row: 10, column: 12)!])
    }

    func testProtectedZonesKeepTheTownOff() throws {
        for zone in [Zone.noDevelopment, .reserved] {
            var world = try world()
            // Every cell beside the town's one cell.
            try world.setZone(zone, rows: 4...6, columns: 4...6)
            world.spread(towards: station(of: world))
            XCTAssertEqual(world.land.cells.count, 1, "\(zone)")
        }
    }

    func testNothingGrowsOnLandZonedNoDevelopment() throws {
        let land = [
            LandCell(row: 5, column: 5, use: .residential, residents: 100, jobs: 0),
            LandCell(row: 5, column: 6, use: .residential, residents: 100, jobs: 0),
        ]
        for (zone, grown) in [(Zone.noDevelopment, Int64(100)), (.reserved, 110), (.commercial, 110)] {
            var world = try world(land: land)
            try world.setZone(zone, rows: 5...5, columns: 6...6)
            // 20 residents shared by 100 and 100: 10 each.
            world.grow(around: station(of: world), residents: 20, jobs: 0)
            XCTAssertEqual(world.land.cell(row: 5, column: 5)?.residents, 110, "\(zone)")
            XCTAssertEqual(world.land.cell(row: 5, column: 6)?.residents, grown, "\(zone)")
        }
    }

    func testNothingIsRaisedOnLandZonedNoDevelopment() throws {
        var world = try world(land: [
            LandCell(row: 5, column: 5, use: .residential, residents: 10, jobs: 0),
            LandCell(row: 5, column: 6, use: .residential, residents: 10, jobs: 0),
        ])
        world.setCityBuildings(true)
        try world.setZone(.noDevelopment, rows: 5...5, columns: 5...5)
        var raised: Set<CellPosition> = []
        let full: Set<CellPosition> = [CellPosition(row: 5, column: 5), CellPosition(row: 5, column: 6)]
        world.raiseBuildings(around: station(of: world), full: full, raised: &raised)
        XCTAssertEqual(world.buildings.building(row: 5, column: 5)?.density, .d1)
        XCTAssertEqual(world.buildings.building(row: 5, column: 6)?.density, .d2)
        XCTAssertEqual(raised, [CellPosition(row: 5, column: 6)])
    }

    // MARK: - Saving

    func testZonesSaveAsRunsAndReadBack() throws {
        var world = try world()
        try world.setZone(.commercial, rows: 1...2, columns: 3...5)
        try world.setZone(.reserved, rows: 2...2, columns: 6...6)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(world)) as? [String: Any])
        let runs = try XCTUnwrap(object["zones"] as? [[String: Any]])
        XCTAssertEqual(runs.count, 3)
        XCTAssertEqual(runs[2]["zone"] as? String, "reserved")
        XCTAssertEqual(runs[1]["count"] as? Int, 3)
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world)), world)

        var none = try self.world()
        try none.setZone(.office, rows: 0...0, columns: 0...0)
        try none.setZone(nil, rows: 0...0, columns: 0...0)
        let plain = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(none)) as? [String: Any])
        XCTAssertNil(plain["zones"], "a world without zones writes none")
    }

    func testDamagedZonesAreRefused() throws {
        let decoder = JSONDecoder()
        XCTAssertThrowsError(try decoder.decode(Zoning.self, from: Data(#"[{"row": 0, "column": 0, "zone": "office", "count": 0}]"#.utf8)))
        XCTAssertThrowsError(try decoder.decode(Zoning.self, from: Data(#"[{"row": 0, "column": -1, "zone": "office", "count": 1}]"#.utf8)))
        XCTAssertThrowsError(try decoder.decode(Zoning.self, from: Data(#"[{"row": 1, "column": 0, "zone": "office", "count": 1}, {"row": 0, "column": 0, "zone": "office", "count": 1}]"#.utf8)))
        XCTAssertThrowsError(try decoder.decode(Zoning.self, from: Data(#"[{"row": 0, "column": 0, "zone": "office", "count": 2}, {"row": 0, "column": 1, "zone": "civic", "count": 1}]"#.utf8)), "a cell twice")
        XCTAssertThrowsError(try decoder.decode(Zoning.self, from: Data(#"[{"row": 0, "column": 0, "zone": "farm", "count": 1}]"#.utf8)))
        // A world refuses a zone outside it: 32 columns, 0 to 31.
        var world = try world()
        try world.setZone(.office, rows: 0...0, columns: 31...31)
        let text = String(decoding: try JSONEncoder().encode(world), as: UTF8.self)
        let outside = text.replacingOccurrences(of: #""column":31"#, with: #""column":32"#)
        XCTAssertNotEqual(outside, text)
        XCTAssertThrowsError(try decoder.decode(GameWorld.self, from: Data(outside.utf8)))
    }

    /// `SaveFixtures/` at the repository root.
    private static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("SaveFixtures", isDirectory: true)

    /// The world of `v23-zoning.json` (decision 98): a managed company with
    /// demand from land and town growth on a world 32 × 24 cells, 1,000
    /// people at a station, a house bought beside it, homes zoned on row 3,
    /// shops on row 10, no development on row 12 and reserved land on row
    /// 14, run ten minutes.
    static func zoningWorld() throws -> GameWorld {
        var world = try GameWorld(
            bounds: WorldBounds(width: 131_072, height: 98_304), economy: GameEconomy(balance: 1_000_000_000, costs: testCosts),
            clock: GameClock(speed: .normal)
        )
        try world.setLand([LandCell(row: 5, column: 5, use: .residential, residents: 1_000, jobs: 0)])
        world.setEconomyMode(.management)
        world.setLandDemand(true)
        world.setTownGrowth(true)
        try world.buildStation(named: "S0", at: PlanPoint(x: 22_528, y: 22_528))
        try world.placeBuilding(.house, at: PlanPoint(x: 24_000, y: 30_000))
        try world.setZone(.residential, rows: 3...3, columns: 3...7)
        try world.setZone(.commercial, rows: 10...10, columns: 4...6)
        try world.setZone(.noDevelopment, rows: 12...12, columns: 0...3)
        try world.setZone(.reserved, rows: 14...14, columns: 10...12)
        try world.advance(ticks: 10)
        return world
    }

    /// Version 23 (decision 98): the zones. It saves byte for byte and is
    /// the world the build that wrote it makes. The version 22 save has
    /// none.
    func testVersionTwentyThreeKeepsTheZones() throws {
        let url = Self.fixtures.appendingPathComponent("v23-zoning.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["ZONING_SAVE_NEW"] != nil {
            try encoder.encode(SavedGame(world: try Self.zoningWorld())).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 23)
        let world = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(world, try Self.zoningWorld())
        XCTAssertEqual(world.zones.cells.count, 15)
        XCTAssertEqual(world.zones.zone(row: 14, column: 11), .reserved)
        XCTAssertEqual(try encoder.encode(SavedGame(world: world)), Data(String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #""saveVersion" : 23,"#, with: #""saveVersion" : \#(SavedGame.currentVersion),"#).utf8))

        let older = try Data(contentsOf: Self.fixtures.appendingPathComponent("v22-company-buildings.json"))
        XCTAssertTrue(try JSONDecoder().decode(SavedGame.self, from: older).world.zones.isEmpty)
    }
}
