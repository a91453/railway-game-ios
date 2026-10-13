import Foundation
@testable import GameCore
import XCTest

/// Sights and tourists (ARCHITECTURE decision 174). Every expectation is
/// worked out by hand from the rules.
final class TourismTests: XCTestCase {
    // MARK: - The rules

    func testPotentialTouristsFollowTheStarsInLines() {
        XCTAssertEqual(Tourism.potentialTourists(stars: 100), 300)
        XCTAssertEqual(Tourism.potentialTourists(stars: 200), 800)
        XCTAssertEqual(Tourism.potentialTourists(stars: 300), 2_000)
        XCTAssertEqual(Tourism.potentialTourists(stars: 400), 4_500)
        XCTAssertEqual(Tourism.potentialTourists(stars: 500), 9_000)
        XCTAssertEqual(Tourism.potentialTourists(stars: 350), 3_250, "half way from 2,000 to 4,500")
        XCTAssertEqual(Tourism.potentialTourists(stars: 325), 2_625)
        XCTAssertEqual(Tourism.potentialTourists(stars: 450), 6_750)
        XCTAssertEqual(Tourism.potentialTourists(stars: 50), 300, "never below one star")
        XCTAssertEqual(Tourism.potentialTourists(stars: 900), 9_000, "never above five")
    }

    func testTheDaySetsTheCrowd() {
        XCTAssertEqual(Tourism.dayFactor(weekday: 1, holiday: false), 600)
        XCTAssertEqual(Tourism.dayFactor(weekday: 5, holiday: false), 600)
        XCTAssertEqual(Tourism.dayFactor(weekday: 6, holiday: false), 1_600)
        XCTAssertEqual(Tourism.dayFactor(weekday: 0, holiday: false), 1_300)
        XCTAssertEqual(Tourism.dayFactor(weekday: 3, holiday: true), 2_000)
        XCTAssertEqual(Tourism.dayFactor(weekday: 6, holiday: true), 2_000)
    }

    func testEachKindHasItsSeason() {
        XCTAssertEqual(Tourism.seasonFactor(.coast, month: 7), 1_500)
        XCTAssertEqual(Tourism.seasonFactor(.coast, month: 12), 500)
        XCTAssertEqual(Tourism.seasonFactor(.coast, month: 2), 500)
        XCTAssertEqual(Tourism.seasonFactor(.coast, month: 4), 1_000)
        XCTAssertEqual(Tourism.seasonFactor(.mountain, month: 10), 1_300)
        XCTAssertEqual(Tourism.seasonFactor(.mountain, month: 1), 1_200)
        XCTAssertEqual(Tourism.seasonFactor(.mountain, month: 8), 800)
        XCTAssertEqual(Tourism.seasonFactor(.mountain, month: 5), 1_000)
        XCTAssertEqual(Tourism.seasonFactor(.hotSpring, month: 11), 1_400)
        XCTAssertEqual(Tourism.seasonFactor(.hotSpring, month: 1), 1_400)
        XCTAssertEqual(Tourism.seasonFactor(.hotSpring, month: 6), 700)
        XCTAssertEqual(Tourism.seasonFactor(.hotSpring, month: 9), 1_000)
        for month in 1...12 { XCTAssertEqual(Tourism.seasonFactor(.town, month: month), 1_000) }
    }

    func testTheCapturedShareIsAFifthRoundedHalfUp() {
        // 2,000 × 0.6 × 1.5 × 0.7 × 0.2 = 252.
        XCTAssertEqual(Tourism.tourists(stars: 300, day: 600, season: 1_500, weather: 700), 252)
        // 300 × 0.6 × 0.2 = 36; 800 × 0.6 × 0.2 = 96; 4,500 × 0.6 × 0.2 = 540.
        XCTAssertEqual(Tourism.tourists(stars: 100, day: 600, season: 1_000, weather: 1_000), 36)
        XCTAssertEqual(Tourism.tourists(stars: 400, day: 600, season: 1_000, weather: 1_000), 540)
        // 300 × 0.5 × 1.0 × 0.7 × 0.2 = 21 exactly; 301 would be 21.07.
        XCTAssertEqual(Tourism.tourists(stars: 100, day: 500, season: 1_000, weather: 700), 21)
        // The most a day can hold: 9,000 × 2 × 1.5 × 1 × 0.2 = 5,400.
        XCTAssertEqual(Tourism.tourists(stars: 500, day: 2_000, season: 1_500, weather: 1_000), 5_400)
    }

    func testAShopAddsAQuarterStarALevelUpToFive() {
        var attraction = Attraction(id: AttractionID(rawValue: 1), name: "a", englishName: "a", point: PlanPoint(x: 0, y: 0),
                                    kind: .town, baseStars: 300)
        XCTAssertEqual(attraction.stars, 300)
        attraction.souvenir = 2
        XCTAssertEqual(attraction.stars, 350)
        let top = Attraction(id: AttractionID(rawValue: 1), name: "a", englishName: "a", point: PlanPoint(x: 0, y: 0),
                             kind: .town, baseStars: 490)
        XCTAssertEqual(top.stars, 490)
        var full = top
        full.souvenir = 2
        XCTAssertEqual(full.stars, 500, "five at most")
    }

    // MARK: - A world

    private let home = StationID(rawValue: 1), foot = StationID(rawValue: 2)

    /// Home (1, residential, 1,000 trips) and Foot (2, scenic, none) on line
    /// Main with a train; a 3-star town 15.6 m from Foot. The world is so
    /// small that both stations are outside connections.
    private func world(attractionAt x: Int64 = 6_632) throws -> GameWorld {
        var world = try GameWorld(bounds: WorldBounds(width: 12_288, height: 3_072), economy: GameEconomy(balance: 100_000_000, costs: testCosts))
        try world.buildStation(named: "Home", at: PlanPoint(x: 1_536, y: 1_536))
        try world.buildStation(named: "Foot", at: PlanPoint(x: 5_632, y: 1_536))
        let line = try world.createLine(named: "Main", stops: [home, foot]).id
        let train = try world.purchaseTrain(named: "T").id
        try world.assignTrain(train, to: line)
        try world.setStationDemand(home, to: StationDemand(kind: .residential, dailyTrips: 1_000))
        try world.setStationDemand(foot, to: StationDemand(kind: .scenic, dailyTrips: 0))
        world.setOutsideConnections(true)
        world.setTourism([Attraction(id: AttractionID(rawValue: 9), name: "老街", englishName: "Old Street",
                                     point: PlanPoint(x: x, y: 1_536), kind: .town, baseStars: 300)])
        return world
    }

    /// A station a line's pattern trains call at serves a sight as one its
    /// own service calls at does (as the company's buildings count it,
    /// decision 173): a line whose only train runs a pattern still brings
    /// the tourists.
    func testAStationOnlyAPatternServesStillServesTheSight() throws {
        var world = try world()
        let line = LineID(rawValue: 1), train = TrainID(rawValue: 1)
        try world.unassignTrain(train)
        let pattern = try world.addLinePattern(line, calling: [0, 1])
        try world.assignTrain(train, to: line, pattern: pattern)
        XCTAssertTrue(world.lines[0].trains.isEmpty)
        let id = AttractionID(rawValue: 1)
        XCTAssertEqual(world.attractionStation(of: id), foot)
        XCTAssertEqual(world.attractionStatus(of: id), .ok)
        XCTAssertEqual(world.dailyDemand(from: home, to: foot), 240)
    }

    func testTouristsRideToTheStationAndBack() throws {
        let world = try world()
        let id = AttractionID(rawValue: 1)
        XCTAssertEqual(world.tourism?.attractions.map(\.id), [id], "numbered from 1")
        XCTAssertEqual(world.attractionStation(of: id), foot)
        XCTAssertEqual(world.attractionStatus(of: id), .ok)
        // Day 0 is a Monday: 2,000 × 0.6 × 0.2 = 240.
        XCTAssertEqual(world.touristsExpected(at: id, onDay: 0), 240)
        XCTAssertEqual(world.dailyDemand(from: home, to: foot), 240)
        XCTAssertEqual(world.dailyDemand(from: foot, to: home), 240, "and they go home")
        XCTAssertEqual(world.hourlyDemand(from: home, to: foot).reduce(0, +), 240)
        XCTAssertEqual(world.hourlyDemand(from: foot, to: home).reduce(0, +), 240)
        // Out by the scenic arrival curve (late morning), back by its
        // departure curve (afternoon).
        let out = world.hourlyDemand(from: home, to: foot), back = world.hourlyDemand(from: foot, to: home)
        XCTAssertGreaterThan(out[10], out[3])
        XCTAssertGreaterThan(back[15], back[3])
    }

    func testThePlanReleasesWhatTheQueriesGive() throws {
        for mode in [PassengerRoutingMode.direct] {
            var world = try world()
            world.setPassengerRoutingMode(mode)
            let plan = try XCTUnwrap(world.makePassengerPlan())
            XCTAssertEqual(plan.flows.map { [$0.origin, $0.destination] }, [[home, foot], [foot, home]], "\(mode)")
            for (index, flow) in plan.flows.enumerated() {
                let day = plan.hourly[index * 24..<(index + 1) * 24].reduce(0, +)
                XCTAssertEqual(day, world.dailyDemand(from: flow.origin, to: flow.destination), "\(mode) \(flow.origin) to \(flow.destination)")
                XCTAssertEqual(day, 240)
            }
        }
    }

    func testAShopRaisesTheStarsAndTheCrowd() throws {
        var world = try world()
        let id = AttractionID(rawValue: 1)
        try world.investInSouvenirShop(of: id)
        XCTAssertEqual(world.attraction(id: id)?.stars, 325)
        // 2,625 × 0.6 × 0.2 = 315.
        XCTAssertEqual(world.touristsExpected(at: id, onDay: 0), 315)
        XCTAssertEqual(world.dailyDemand(from: home, to: foot), 315, "the plan was worked out again")
        try world.investInSouvenirShop(of: id)
        XCTAssertEqual(world.attraction(id: id)?.souvenir, 2)
        XCTAssertThrowsError(try world.investInSouvenirShop(of: id)) { XCTAssertEqual($0 as? GameError, .attractionMaxedOut) }
        XCTAssertThrowsError(try world.investInSouvenirShop(of: AttractionID(rawValue: 5))) {
            XCTAssertEqual($0 as? GameError, .unknownAttraction(AttractionID(rawValue: 5)))
        }
    }

    /// Tourism turned off or set again takes the shops' records off the
    /// books (written off, as a station's when it goes): a record naming a
    /// shop that no longer exists would make the save unloadable.
    func testSettingTourismAgainTakesTheShopsOffTheBooks() throws {
        for replacement in [nil, [Attraction(id: AttractionID(rawValue: 1), name: "海", englishName: "Sea",
                                            point: PlanPoint(x: 9_000, y: 1_536), kind: .coast, baseStars: 200)]] {
            var world = try world()
            world.setEconomyMode(.management)
            try world.investInSouvenirShop(of: AttractionID(rawValue: 1))
            XCTAssertEqual(world.accounts.assets.filter { $0.kind == .souvenirShop }.count, 1)
            world.setTourism(replacement)
            XCTAssertTrue(world.accounts.assets.filter { $0.kind == .souvenirShop }.isEmpty)
            XCTAssertEqual(world.accounts.capitalDays.last?.writeOff, Money(30_000_000))
            let data = try JSONEncoder().encode(SavedGame(world: world))
            XCTAssertEqual(try JSONDecoder().decode(SavedGame.self, from: data).world, world)
        }
    }

    func testAShopCostsThreeHundredThousandALevelAndIsAnAsset() throws {
        var world = try world()
        let before = world.economy.balance
        try world.investInSouvenirShop(of: AttractionID(rawValue: 1))
        XCTAssertEqual(before - world.economy.balance, Money(30_000_000))
        // Free play keeps no accounts.
        XCTAssertTrue(world.accounts.assets.isEmpty)
        var poor = try self.world()
        poor.setEconomyMode(.management)
        let record = try { () throws -> AssetRecord in
            try poor.investInSouvenirShop(of: AttractionID(rawValue: 1))
            try poor.investInSouvenirShop(of: AttractionID(rawValue: 1))
            return try XCTUnwrap(poor.accounts.assets.first { $0.kind == .souvenirShop })
        }()
        XCTAssertEqual(poor.accounts.assets.filter { $0.kind == .souvenirShop }.map(\.cost), [Money(30_000_000), Money(30_000_000)], "a record a level")
        XCTAssertEqual(record.cost, Money(30_000_000))
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(poor)), poor)
    }

    /// The second level is written down from when it was bought, on its own
    /// schedule (NEXT_PRIORITIES §2): added to the first level's record, its
    /// cost was caught up on that record's days the next day, and never
    /// written down once the first level was.
    func testTheSecondLevelIsWrittenDownFromWhenItWasBought() throws {
        let life = AssetClass.buildings.lifeDays
        let daily = Money(30_000_000 / life)
        for daysWritten in [Int64(100), life] {
            var world = try self.world()
            world.setEconomyMode(.management)
            try world.investInSouvenirShop(of: AttractionID(rawValue: 1))
            for _ in 0 ..< daysWritten { world.depreciateAssets(day: 0) }
            XCTAssertEqual(world.accounts.assets.first { $0.kind == .souvenirShop }?.days, daysWritten)
            try world.investInSouvenirShop(of: AttractionID(rawValue: 1))
            let before = world.accounts.assets.reduce(Money.zero) { $0 + $1.depreciation }
            world.depreciateAssets(day: 0)
            let charge = world.accounts.assets.reduce(Money.zero) { $0 + $1.depreciation } - before
            // A day of each level still being written down, give or take
            // the cent the straight line rounds off.
            let levels: Int64 = daysWritten < life ? 2 : 1
            XCTAssertLessThanOrEqual(abs(charge.amount - daily.amount * levels), levels, "after \(daysWritten) days")
            XCTAssertNil(world.assetsProblem())
            XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world)), world)
        }
    }

    func testNoStationWithinEightHundredMetres() throws {
        // 51,200 units is 800 m: Foot at 5,632 and an attraction 51,200 away
        // is in reach, one unit further is not.
        let near = try world(attractionAt: 5_632 + 51_200)
        XCTAssertEqual(near.attractionStatus(of: AttractionID(rawValue: 1)), .ok)
        let far = try world(attractionAt: 5_632 + 51_201)
        XCTAssertEqual(far.attractionStatus(of: AttractionID(rawValue: 1)), .noStation)
        XCTAssertEqual(far.dailyDemand(from: home, to: foot), 0)
        XCTAssertNil(far.attractionStation(of: AttractionID(rawValue: 1)))
    }

    func testNoTrainNoStop() throws {
        var world = try world()
        try world.unassignTrain(TrainID(rawValue: 1))
        XCTAssertEqual(world.attractionStatus(of: AttractionID(rawValue: 1)), .noStation)
    }

    func testNoSourceWhenNobodyCanRideThere() throws {
        var world = try world()
        // A third station on a line of its own is not reached from Home.
        try world.buildStation(named: "Far", at: PlanPoint(x: 9_000, y: 1_536))
        try world.buildStation(named: "Farther", at: PlanPoint(x: 10_500, y: 1_536))
        try world.setStationDemand(StationID(rawValue: 3), to: StationDemand(kind: .scenic, dailyTrips: 0))
        try world.setStationDemand(StationID(rawValue: 4), to: StationDemand(kind: .scenic, dailyTrips: 0))
        try world.setStationOperationMode(StationID(rawValue: 4), to: .closed)
        let line = try world.createLine(named: "Other", stops: [StationID(rawValue: 3), StationID(rawValue: 4)]).id
        let train = try world.purchaseTrain(named: "U").id
        try world.assignTrain(train, to: line)
        var elsewhere = world
        elsewhere.setTourism([Attraction(id: AttractionID(rawValue: 1), name: "x", englishName: "x", point: PlanPoint(x: 9_100, y: 1_536),
                                         kind: .town, baseStars: 300)])
        XCTAssertEqual(elsewhere.attractionStation(of: AttractionID(rawValue: 1)), StationID(rawValue: 3))
        XCTAssertEqual(elsewhere.attractionStatus(of: AttractionID(rawValue: 1)), .noSource)
    }

    func testAWeekendHolidayAndRainChangeTheCrowd() throws {
        var world = try world()
        let id = AttractionID(rawValue: 1)
        // Day 5 is a Saturday (a game starts on a Monday): 2,000 × 1.6 × 0.2 = 640; day 6 a Sunday: 520.
        XCTAssertEqual(world.touristsExpected(at: id, onDay: 5), 640)
        XCTAssertEqual(world.touristsExpected(at: id, onDay: 6), 520)
        // New Year's Day (day 0) is a holiday, ×2: 2,000 × 2 × 0.2 = 800.
        world.setDisruptions(Disruptions(level: .standard, country: "TW", seed: 7)!)
        XCTAssertEqual(world.touristsExpected(at: id, onDay: 0), 800)
        // Rain takes three tenths whatever the day.
        let rainy = (0..<360).first { world.weather(onDay: Int64($0)) == .rain && world.holiday(onDay: Int64($0)) == nil }
        let day = Int64(try XCTUnwrap(rainy))
        let weekday = StationDemand.weekday(ofDay: day)
        let factor = Tourism.dayFactor(weekday: weekday, holiday: false)
        let season = Tourism.seasonFactor(.town, month: Int(day / 30) + 1)
        XCTAssertEqual(world.touristsExpected(at: id, onDay: day), Tourism.tourists(stars: 300, day: factor, season: season, weather: 700))
    }

    func testMidnightCountsTheDayAndTheShopPays() throws {
        var world = try world()
        world.setEconomyMode(.management)
        try world.investInSouvenirShop(of: AttractionID(rawValue: 1))
        // Day 0 is a Monday: 2,625 × 0.6 × 0.2 = 315 tourists.
        world.setSpeed(.normal)
        try world.advance(ticks: 1_442)
        let attraction = try XCTUnwrap(world.attraction(id: AttractionID(rawValue: 1)))
        XCTAssertEqual(attraction.yesterday, 315)
        XCTAssertEqual(attraction.thisYear, 315)
        // 315 tourists spend $4 × 1 in the shop: $1,260; upkeep 0.05% of $300,000 = $150.
        let row = try XCTUnwrap(world.accounts.entries.last { $0.kind == .dailyTourism })
        XCTAssertEqual(row.breakdown, [
            LedgerLine(item: .tourismRevenue, amount: Money(126_000)),
            LedgerLine(item: .tourismUpkeep, amount: Money(-15_000)),
        ])
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world)), world)
    }

    func testTheYearTurnsAtThreeHundredAndSixtyDays() throws {
        var world = try world()
        world.setSpeed(.normal)
        try world.advance(ticks: 1_442)
        XCTAssertEqual(world.attraction(id: AttractionID(rawValue: 1))?.thisYear, 240)
        // Closing day 360 (the first of year 1) moves the count to last year.
        world.closeTourismDay(359)
        XCTAssertEqual(world.attraction(id: AttractionID(rawValue: 1))?.thisYear, 480)
        world.closeTourismDay(360)
        let attraction = try XCTUnwrap(world.attraction(id: AttractionID(rawValue: 1)))
        XCTAssertEqual(attraction.lastYear, 480)
        XCTAssertEqual(attraction.thisYear, attraction.yesterday)
        XCTAssertEqual(world.tourism?.year, 1)
    }

    func testASaveKeepsTourismAndTurnsOffWithNil() throws {
        var world = try world()
        try world.investInSouvenirShop(of: AttractionID(rawValue: 1))
        let data = try JSONEncoder().encode(SavedGame(world: world))
        let loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(loaded, world)
        XCTAssertEqual(loaded.tourism?.attractions.first?.souvenir, 1)
        world.setTourism(nil)
        XCTAssertNil(world.tourism)
        XCTAssertEqual(world.dailyDemand(from: home, to: foot), 0)
        XCTAssertThrowsError(try world.investInSouvenirShop(of: AttractionID(rawValue: 1))) {
            XCTAssertEqual($0 as? GameError, .tourismNotEnabled)
        }
    }

    /// The committed version 47 save: Home and Foot with the Old Street sight
    /// (a 3-star town) and a level 1 souvenir shop in a managed company, run
    /// a day and two minutes, so that it has counted the first day's 315
    /// tourists and booked the shop's takings. It saves byte for byte.
    func testVersionFortySevenKeepsTourism() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SaveFixtures/v47-tourism.json")
        var made = try world()
        made.setEconomyMode(.management)
        try made.investInSouvenirShop(of: AttractionID(rawValue: 1))
        made.setSpeed(.normal)
        try made.advance(ticks: 1_442)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["TOURISM_SAVE_NEW"] != nil {
            try encoder.encode(SavedGame(world: made)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 47)
        let loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(loaded, made)
        let sight = try XCTUnwrap(loaded.attraction(id: AttractionID(rawValue: 1)))
        XCTAssertEqual(sight.souvenir, 1)
        XCTAssertEqual(sight.yesterday, 315)
        XCTAssertEqual(sight.thisYear, 315)
        XCTAssertEqual(loaded.accounts.assets.filter { $0.kind == .souvenirShop }.map(\.cost), [Money(30_000_000)])
        XCTAssertEqual(try encoder.encode(SavedGame(world: loaded)), Data(String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #""saveVersion" : 47,"#, with: #""saveVersion" : \#(SavedGame.currentVersion),"#).utf8))
    }

    /// A save from before decision 174 has no tourism.
    func testAnEarlierSaveReadsWithoutTourism() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SaveFixtures/v44-door-crowding.json")
        let world = try JSONDecoder().decode(SavedGame.self, from: Data(contentsOf: url)).world
        XCTAssertNil(world.tourism)
    }

    // MARK: - Network routing

    /// Four stations on a track, a train on their line, a 3-star sight by the
    /// last: the tourists of a network game come over routes of the track,
    /// and the plan releases what the queries give.
    func testNetworkTouristsRideTheTrackAndTheNetworkPlanAgrees() throws {
        var world = try GameWorld(bounds: WorldBounds(width: 16_384, height: 4_096), economy: GameEconomy(balance: 1_000_000_000, costs: testCosts))
        let track = TestLine(tiles: 14)
        try track.build(in: &world)
        let ids = (1...4).map { StationID(rawValue: $0) }
        for (index, x) in [1, 5, 9, 13].enumerated() {
            try track.buildStation(named: "S\(index)", beside: x, at: 1, in: &world)
        }
        let line = try world.createLine(named: "L", stops: ids).id
        try world.setLineServiceWindow(line, to: .allDay)
        try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        try world.assignTrain(try world.purchaseTrain(named: "T").id, to: line)
        for (index, id) in ids.enumerated() {
            try world.setStationDemand(id, to: StationDemand(kind: index == 3 ? .scenic : .residential, dailyTrips: index == 3 ? 0 : 1_000))
        }
        world.setPassengerRoutingMode(.network)
        world.setOutsideConnections(true)
        let last = try XCTUnwrap(world.station(id: ids[3]))
        world.setTourism([Attraction(id: AttractionID(rawValue: 1), name: "x", englishName: "x",
                                     point: PlanPoint(x: last.point.x + 1_000, y: last.point.y), kind: .town, baseStars: 300)])
        XCTAssertEqual(world.attractionStation(of: AttractionID(rawValue: 1)), ids[3])
        XCTAssertEqual(world.attractionStatus(of: AttractionID(rawValue: 1)), .ok)
        let plan = try XCTUnwrap(world.makePassengerPlan())
        var tourists: Int64 = 0
        for (index, flow) in plan.flows.enumerated() {
            let day = plan.hourly[index * 24..<(index + 1) * 24].reduce(0, +)
            XCTAssertEqual(day, world.dailyDemand(from: flow.origin, to: flow.destination), "\(flow.origin) to \(flow.destination)")
            XCTAssertEqual(plan.hourly[index * 24..<(index + 1) * 24].count, 24)
            if flow.destination == ids[3] { tourists += world.dailyDemand(from: flow.origin, to: flow.destination) }
        }
        // The 240 tourists of a Monday; Foot draws none of the ordinary trips
        // (no demand of its own to weigh).
        XCTAssertEqual(tourists, 240)
        // The same day's plan, kept: it is rebuilt when the sight changes.
        var kept = world
        try kept.advance(ticks: 1)
        let before = try XCTUnwrap(kept.dailyDemand(from: ids[0], to: ids[3]) as Int64?)
        try kept.investInSouvenirShop(of: AttractionID(rawValue: 1))
        XCTAssertGreaterThan(kept.dailyDemand(from: ids[0], to: ids[3]), before)
    }
}
