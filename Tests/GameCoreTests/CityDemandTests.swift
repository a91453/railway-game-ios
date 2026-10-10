import Foundation
@testable import GameCore
import XCTest

/// The city's demand for homes, shops and work (ARCHITECTURE decision 139).
/// Every number below is worked out by hand.
final class CityDemandTests: XCTestCase {
    /// 32 × 24 cells.
    private static let small = try! WorldBounds(width: 131_072, height: 98_304)
    /// Station S0 stands at the middle of cell (5, 5).
    private static let stationPoint = PlanPoint(x: 22_528, y: 22_528)

    /// Homes of 300 at (5, 5), shops of 40 living and 300 working at (5, 6)
    /// and offices of 600 jobs at (5, 7): all within S0's front (256 m).
    private static let town = [
        LandCell(row: 5, column: 5, use: .residential, residents: 300, jobs: 0),
        LandCell(row: 5, column: 6, use: .commercial, residents: 40, jobs: 300),
        LandCell(row: 5, column: 7, use: .office, residents: 0, jobs: 600),
    ]

    /// A managed world whose land sets ridership with town growth on and the
    /// station S0.
    private func world(land: [LandCell] = town) throws -> GameWorld {
        var world = GameWorld(bounds: Self.small, economy: GameEconomy(balance: 1_000_000_000, costs: testCosts), clock: GameClock(speed: .normal))
        try world.setLand(land)
        world.setEconomyMode(.management)
        world.setLandDemand(true)
        world.setTownGrowth(true)
        try world.buildStation(named: "S0", at: Self.stationPoint)
        return world
    }

    // MARK: - The mix and the levels

    func testTheMixIsEachKindOfJobForAMillionResidents() {
        var land = Land()
        land.cells = [
            LandCell(row: 0, column: 0, use: .residential, residents: 1_000, jobs: 0),
            LandCell(row: 0, column: 1, use: .commercial, residents: 100, jobs: 300),
            LandCell(row: 0, column: 2, use: .office, residents: 50, jobs: 600),
            LandCell(row: 0, column: 3, use: .industrial, residents: 0, jobs: 200),
            LandCell(row: 0, column: 4, use: .agricultural, residents: 3, jobs: 8),
            LandCell(row: 0, column: 5, use: .civic, residents: 10, jobs: 40),
            LandCell(row: 0, column: 6, use: .leisure, residents: 0, jobs: 30),
            LandCell(row: 0, column: 7, use: .park, residents: 0, jobs: 0),
        ]
        // 1,163 residents; 300 shop jobs; 600 + 200 + 8 = 808 in work;
        // schools and sights count for neither.
        XCTAssertEqual(CityMix(of: land), CityMix(shopJobs: 300_000_000 / 1_163, workJobs: 808_000_000 / 1_163))
        XCTAssertEqual(CityMix(of: land), CityMix(shopJobs: 257_953, workJobs: 694_754))

        land.cells = [LandCell(row: 0, column: 3, use: .industrial, residents: 0, jobs: 200)]
        XCTAssertNil(CityMix(of: land), "no one lives there")
        XCTAssertNil(CityMix(of: Land()))
    }

    func testEachLevelIsTenTimesItsDriftFromTheMixKept() {
        let demand = CityDemand(baseline: CityMix(shopJobs: 400_000, workJobs: 600_000))
        // Shops: 10 × 1000 × (400,000 − 440,000) / 440,000 = −909.09, toward
        // 0; work: 10 × 1000 × 60,000 / 600,000 = 1000; homes: jobs a
        // resident 980,000 against 1,000,000, −200.
        XCTAssertEqual(demand.levels(now: CityMix(shopJobs: 440_000, workJobs: 540_000)),
                       CityDemand.Levels(homes: -200, shops: -909, work: 1_000))
        // A quarter too few shops is past full demand.
        XCTAssertEqual(demand.levels(now: CityMix(shopJobs: 300_000, workJobs: 600_000)).shops, 1_000)
        XCTAssertEqual(demand.levels(now: CityMix(shopJobs: 400_000, workJobs: 600_000)), .none)
        XCTAssertEqual(demand.levels(now: nil), .none)
        XCTAssertEqual(CityDemand().levels(now: CityMix(shopJobs: 1, workJobs: 1)), .none, "no mix kept yet")
        XCTAssertEqual(CityDemand(baseline: CityMix(shopJobs: 0, workJobs: 0)).levels(now: CityMix(shopJobs: 0, workJobs: 0)), .none)

        let levels = CityDemand.Levels(homes: 1, shops: 2, work: 3)
        XCTAssertEqual([LandUse.residential, .commercial, .office, .industrial].map(levels.level(of:)), [1, 2, 3, 3])
        XCTAssertEqual([LandUse.agricultural, .civic, .leisure, .park].map(levels.level(of:)), [nil, nil, nil, nil])
    }

    // MARK: - The command

    func testTheCityKeepsTheMixItHasWhenTheValvesOpen() throws {
        var world = try world()
        XCTAssertNil(world.cityDemand)
        XCTAssertEqual(world.cityDemandLevels, .none)
        world.setCityDemand(true)
        // 340 residents, 300 shop jobs and 600 in work.
        let mix = CityMix(shopJobs: 882_352, workJobs: 1_764_705)
        XCTAssertEqual(world.cityDemand, CityDemand(baseline: mix))
        XCTAssertEqual(world.cityDemandLevels, .none)

        // More homes: fewer jobs a resident, so shops and work are wanted.
        try world.setLand(Self.town + [LandCell(row: 10, column: 10, use: .residential, residents: 34, jobs: 0)])
        XCTAssertEqual(world.cityDemand?.baseline, CityMix(shopJobs: 802_139, workJobs: 1_604_278), "new land, a new mix")
        world.settleCityMix()
        XCTAssertEqual(world.cityDemand?.baseline, CityMix(shopJobs: 802_139, workJobs: 1_604_278), "kept once it has one")

        world.setCityDemand(false)
        XCTAssertNil(world.cityDemand)
        // With no one living there the mix waits for the first midnight
        // with residents.
        try world.setLand([])
        world.setCityDemand(true)
        XCTAssertEqual(world.cityDemand, CityDemand(baseline: nil))
        world.settleCityMix()
        XCTAssertEqual(world.cityDemand, CityDemand(baseline: nil))
        world.land.cells = Self.town
        world.settleCityMix()
        XCTAssertEqual(world.cityDemand?.baseline, mix)
    }

    // MARK: - Growth

    /// S0's day of growth at 1 %: residents 340 and the front's 340 twice
    /// more give ⌊(1020 × 10 + 500) / 1000⌋ = 10, jobs 900 and 1,800 give
    /// 27; 37 in all, none of schools or sights. The mix's weights a
    /// thousand residents: 1,000,000, 882 × 1000 and 1,764 × 1000; 10.15,
    /// 8.95 and 17.90 by the largest remainder: 10, 9 and 18. The residents
    /// go 900 : 120 by the front's weight, 8.82 and 1.18: 9 and 1; the shop
    /// jobs all to the shops and the work all to the offices.
    func testAStationsGrowthIsSharedByTheMixKeptAndTheDemand() throws {
        var world = try world()
        world.setCityDemand(true)
        let mix = try XCTUnwrap(world.cityDemand?.baseline)
        let share = try XCTUnwrap(LandDemand.shares(of: world.land, among: world.stations)[world.stations[0].id])
        world.growSteered(around: world.stations[0], share: share, rate: 10, levels: .none, mix: mix)
        XCTAssertEqual(world.land.cells, [
            LandCell(row: 5, column: 5, use: .residential, residents: 309, jobs: 0),
            LandCell(row: 5, column: 6, use: .commercial, residents: 41, jobs: 309),
            LandCell(row: 5, column: 7, use: .office, residents: 0, jobs: 618),
        ])

        // With no demand for shops their weight is 0: 37 over 1,000,000
        // and 1,764,000, 13.39 and 23.61: 13 and 24.
        var steered = try self.world()
        steered.setCityDemand(true)
        steered.growSteered(around: steered.stations[0], share: share, rate: 10, levels: CityDemand.Levels(homes: 0, shops: -1_000, work: 0), mix: mix)
        let residents = steered.land.cells.reduce(Int64(0)) { $0 + $1.residents }
        XCTAssertEqual(residents, 340 + 13)
        XCTAssertEqual(steered.land.cell(row: 5, column: 6)?.jobs, 300)
        XCTAssertEqual(steered.land.cell(row: 5, column: 7)?.jobs, 624)
    }

    /// Three full D1 buildings, two raised a night: by row and column
    /// without the valves, the most wanted use first with them.
    func testTheMostWantedUseIsRaisedFirst() throws {
        var world = try world(land: [
            LandCell(row: 5, column: 5, use: .residential, residents: 100, jobs: 0),
            LandCell(row: 5, column: 8, use: .commercial, residents: 10, jobs: 100),
            LandCell(row: 5, column: 9, use: .office, residents: 10, jobs: 100),
        ])
        world.setCityBuildings(true)
        let full: Set<CellPosition> = [CellPosition(row: 5, column: 5), CellPosition(row: 5, column: 8), CellPosition(row: 5, column: 9)]
        var raised: Set<CellPosition> = []
        var steered = world
        steered.raiseBuildings(around: steered.stations[0], full: full, raised: &raised, levels: CityDemand.Levels(homes: -1, shops: 0, work: 5))
        XCTAssertEqual(raised, [CellPosition(row: 5, column: 9), CellPosition(row: 5, column: 8)], "work, then shops; homes wait")
        raised = []
        steered = world
        steered.raiseBuildings(around: steered.stations[0], full: full, raised: &raised, levels: CityDemand.Levels.none)
        XCTAssertEqual(raised, [CellPosition(row: 5, column: 5), CellPosition(row: 5, column: 8)], "all equal: by row and column")
        raised = []
        world.raiseBuildings(around: world.stations[0], full: full, raised: &raised, levels: nil)
        XCTAssertEqual(raised, [CellPosition(row: 5, column: 5), CellPosition(row: 5, column: 8)], "without the valves, as before")
    }

    /// The offices are full (1,200 jobs, the limit without the city's
    /// buildings): work has no room. Jobs 1,500 in all give 45 grown, 55
    /// with the residents' 10; the mix's weights 1,000,000, 882 × 1000 and
    /// 3,529 × 1000 give 10, 9 and 36. The 36 of work go to residents and
    /// shops by the plain mix, 1000 : 882: 19.13 and 16.87, 19 and 17. So
    /// 29 residents (26 and 3) and 26 shop jobs.
    func testWhatAKindHasNoRoomForGoesToTheOthers() throws {
        var world = try world(land: [
            LandCell(row: 5, column: 5, use: .residential, residents: 300, jobs: 0),
            LandCell(row: 5, column: 6, use: .commercial, residents: 40, jobs: 300),
            LandCell(row: 5, column: 7, use: .office, residents: 0, jobs: 1_200),
        ])
        world.setCityDemand(true)
        let mix = try XCTUnwrap(world.cityDemand?.baseline)
        XCTAssertEqual(mix, CityMix(shopJobs: 882_352, workJobs: 3_529_411))
        let share = try XCTUnwrap(LandDemand.shares(of: world.land, among: world.stations)[world.stations[0].id])
        world.growSteered(around: world.stations[0], share: share, rate: 10, levels: .none, mix: mix)
        XCTAssertEqual(world.land.cells, [
            LandCell(row: 5, column: 5, use: .residential, residents: 326, jobs: 0),
            LandCell(row: 5, column: 6, use: .commercial, residents: 43, jobs: 326),
            LandCell(row: 5, column: 7, use: .office, residents: 0, jobs: 1_200),
        ])
    }

    func testTheNewCellIsTheUseMostInDemand() throws {
        let cases: [(CityDemand.Levels, LandCell)] = [
            (.none, LandCell(row: 4, column: 5, use: .residential, residents: 4, jobs: 0)),
            (CityDemand.Levels(homes: -10, shops: -5, work: -1), LandCell(row: 4, column: 5, use: .residential, residents: 4, jobs: 0)),
            (CityDemand.Levels(homes: 10, shops: 20, work: 20), LandCell(row: 4, column: 5, use: .commercial, residents: 1, jobs: 12)),
            (CityDemand.Levels(homes: 10, shops: 20, work: 30), LandCell(row: 4, column: 5, use: .office, residents: 1, jobs: 12)),
            (CityDemand.Levels(homes: 30, shops: 20, work: 30), LandCell(row: 4, column: 5, use: .residential, residents: 4, jobs: 0)),
        ]
        for (levels, cell) in cases {
            var world = try world(land: [LandCell(row: 5, column: 5, use: .residential, residents: 1_000, jobs: 0)])
            world.spread(towards: world.stations[0], levels: levels)
            // The four cells beside (5, 5) are equally near: by row, (4, 5).
            XCTAssertEqual(world.land.cell(row: 4, column: 5), cell, "\(levels)")
        }
    }

    func testAZonedCellIsBuiltOnlyWhileItsUseIsWanted() throws {
        var world = try world(land: [LandCell(row: 5, column: 5, use: .residential, residents: 1_000, jobs: 0)])
        try world.setZone(.commercial, rows: 10...10, columns: 5...5)
        try world.setZone(.civic, rows: 12...12, columns: 5...5)
        var unwanted = world
        unwanted.spread(towards: unwanted.stations[0], levels: CityDemand.Levels(homes: 0, shops: -1, work: 0))
        XCTAssertNil(unwanted.land.cell(row: 10, column: 5), "shops are not wanted")
        XCTAssertEqual(unwanted.land.cell(row: 12, column: 5)?.use, .civic, "schools are always built")
        world.spread(towards: world.stations[0], levels: CityDemand.Levels(homes: 0, shops: 0, work: 0))
        XCTAssertEqual(world.land.cell(row: 10, column: 5)?.use, .commercial, "the zoned cell worth most, at no negative demand")
    }

    /// A city with no one living in it when the valves opened takes its
    /// mix at the first midnight with residents.
    func testTheFirstMidnightWithResidentsSettlesTheMix() throws {
        var world = try world(land: [])
        world.setCityDemand(true)
        world.growLand(reached: [:])
        XCTAssertEqual(world.cityDemand, CityDemand(baseline: nil))
        world.land.cells = Self.town
        world.growLand(reached: [:])
        XCTAssertEqual(world.cityDemand?.baseline, CityMix(shopJobs: 882_352, workJobs: 1_764_705))
    }

    /// Land read in as it is needed (decision 88) is not the city growing:
    /// a block read in counts in the mix kept, so the demand of the land
    /// already read stays as it was. Land read afresh drops the mix kept,
    /// which the first midnight with residents then settles again.
    func testLandReadInIsNotTheCityGrowing() throws {
        var world = GameWorld(bounds: try WorldBounds(width: 1 << 22, height: 1 << 22),
                              economy: GameEconomy(balance: 1_000_000_000, costs: testCosts), clock: GameClock(speed: .normal))
        world.setEconomyMode(.management)
        world.setLandDemand(true)
        world.setLandOnDemand()
        world.setCityDemand(true)
        try world.expandLand([LandBlock(row: 0, column: 0)], cells: [
            LandCell(row: 1, column: 1, use: .residential, residents: 1_000, jobs: 0),
            LandCell(row: 1, column: 2, use: .commercial, residents: 0, jobs: 400),
            LandCell(row: 1, column: 3, use: .office, residents: 0, jobs: 400),
        ])
        world.settleCityMix()
        XCTAssertEqual(world.cityDemand?.baseline, CityMix(shopJobs: 400_000, workJobs: 400_000))

        // An office district elsewhere: 10 living, 5,000 working.
        try world.expandLand([LandBlock(row: 0, column: 1)], cells: [
            LandCell(row: 1, column: 20, use: .office, residents: 10, jobs: 5_000),
        ])
        XCTAssertEqual(world.cityDemand?.baseline, CityMix(shopJobs: 396_039, workJobs: 5_346_534))
        XCTAssertEqual(world.cityDemandLevels, CityDemand.Levels(homes: 0, shops: 0, work: 0))

        world.setLandOnDemand()
        XCTAssertEqual(world.cityDemand, CityDemand(baseline: nil))
    }

    // MARK: - Saving

    func testTheMixSavesAndBadOnesAreRefused() throws {
        var world = try world()
        let off = String(decoding: try JSONEncoder().encode(world), as: UTF8.self)
        XCTAssertFalse(off.contains("cityDemand"))
        world.setCityDemand(true)
        let data = try JSONEncoder().encode(world)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains(#""cityDemand":{"baseline":{"#), json)
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: data), world)

        let waiting = try JSONEncoder().encode(CityDemand())
        XCTAssertEqual(String(decoding: waiting, as: UTF8.self), "{}")
        XCTAssertEqual(try JSONDecoder().decode(CityDemand.self, from: waiting), CityDemand())
        for broken in [#"{"baseline":{"shopJobs":-1,"workJobs":0}}"#, #"{"baseline":{"shopJobs":0,"workJobs":1000000000001}}"#] {
            XCTAssertThrowsError(try JSONDecoder().decode(CityDemand.self, from: Data(broken.utf8)), broken)
        }
    }

    /// Version 32 (decision 139): `world()` with the valves on and a day and
    /// a minute run, measured as the test of growth sets it. It saves byte
    /// for byte and is the world this build makes.
    func testVersionThirtyTwoKeepsTheCitysDemand() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SaveFixtures/v32-city-demand.json")
        var made = try world()
        made.setCityDemand(true)
        try made.setZone(.office, rows: 8...8, columns: 5...7)
        try made.advance(ticks: 1 + 1_440)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["CITY_DEMAND_SAVE_NEW"] != nil {
            try encoder.encode(SavedGame(world: made)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 32)
        let world = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(world, made)
        XCTAssertEqual(world.cityDemand?.baseline, CityMix(shopJobs: 882_352, workJobs: 1_764_705))
        XCTAssertEqual(try encoder.encode(SavedGame(world: world)), Data(String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #""saveVersion" : 32,"#, with: #""saveVersion" : \#(SavedGame.currentVersion),"#).utf8))
    }
}
