import Foundation
@testable import GameCore
import XCTest

/// Harbours (decision 773): fishing ports and fisherman's wharves, their
/// own hours, season and weather. Every expectation is worked out from the
/// rules.
final class HarbourSightsTests: XCTestCase {
    // MARK: - The hours

    private func g(_ h: Double, _ mu: Double, _ sigma: Double) -> Double {
        exp(-0.5 * pow((h - mu) / sigma, 2))
    }

    /// `f(h)` normalised to a day's mean of 1, in thousandths, rounded half up.
    private func curve(_ f: (Double) -> Double) -> [Int64] {
        let raw = (0..<24).map { f(Double($0)) }
        let mean = raw.reduce(0, +) / 24
        return raw.map { Int64(($0 / mean * 1_000).rounded()) }
    }

    func testTheTablesAreTheFormula() {
        XCTAssertEqual(Tourism.harbourArrivals, curve { 0.02 + 0.5 * self.g($0, 11.5, 1.5) + 0.5 * self.g($0, 16.5, 1.5) })
        XCTAssertEqual(Tourism.harbourDepartures, curve { 0.02 + 0.5 * self.g($0, 13.5, 1.5) + 0.5 * self.g($0, 19, 1.5) })
    }

    func testTheHoursAreLunchAndSunset() {
        let arrivals = Tourism.harbourArrivals, departures = Tourism.harbourDepartures
        // Two waves in, at lunch and before sunset, with a lull between.
        XCTAssertGreaterThan(arrivals[12], arrivals[14])
        XCTAssertGreaterThan(arrivals[16], arrivals[14])
        XCTAssertLessThan(arrivals[7] * 10, arrivals[12])
        // The last leave after the sunset's dinner, later than a beach's scenic curve would.
        XCTAssertEqual(departures.firstIndex(of: departures.max()!), 19)
        XCTAssertGreaterThan(departures[20], departures[16])
        XCTAssertEqual(Tourism.hours(of: .harbour)?.arrivals, arrivals)
        XCTAssertNil(Tourism.hours(of: .coast))
    }

    func testTheNewKindIsLastSoABlankMapDrawsTheSameKinds() {
        XCTAssertEqual(AttractionKind.allCases, [.coast, .mountain, .hotSpring, .town, .nightMarket, .landmark, .museum, .temple, .harbour])
        XCTAssertTrue(GameWorld.attractionNames[.coast]!.contains { $0.english == GameWorld.blankHarbourName })
        XCTAssertNil(GameWorld.attractionNames[.harbour])
    }

    // MARK: - Seasons and weather

    func testTheSeasonIsTheOfficialCountsNearlyFlat() {
        XCTAssertEqual((1...12).map { Tourism.seasonFactor(.harbour, month: $0) },
                       [900, 1_000, 1_000, 1_000, 1_000, 1_000, 1_000, 1_000, 1_000, 1_000, 1_000, 900])
        XCTAssertEqual(Tourism.seasonFactor(.coast, month: 7), 1_500)
        XCTAssertEqual(Tourism.seasonFactor(.coast, month: 1), 500)
    }

    func testRainAndStormsKeepMoreAway() {
        XCTAssertEqual(Tourism.weatherFactor(.harbour, weather: .clear), 1_000)
        XCTAssertEqual(Tourism.weatherFactor(.harbour, weather: .rain), 600)
        XCTAssertEqual(Tourism.weatherFactor(.harbour, weather: .thunderstorm), 300)
        XCTAssertEqual(Tourism.weatherFactor(.coast, weather: .thunderstorm), 700)
        XCTAssertEqual(Tourism.weatherFactor(.museum, weather: .thunderstorm), 1_100)
        XCTAssertEqual(Tourism.weatherFactor(.harbour, clear: false), 600)
        XCTAssertEqual(Tourism.dayFactor(.harbour, weekday: 1, holiday: nil, dayOfMonth: 1), 600, "a weekday's, no closing day")
    }

    // MARK: - A world

    private let home = StationID(rawValue: 1), foot = StationID(rawValue: 2)

    /// `SightKindsTests`' world: Home (residential) and Foot (scenic) on
    /// line Main with a train, a 3-star sight of `kind` 15.6 m from Foot.
    private func world(_ kind: AttractionKind) throws -> GameWorld {
        var world = try GameWorld(bounds: WorldBounds(width: 12_288, height: 3_072), economy: fixtureEconomy(balance: 300_000_000, costs: testCosts))
        try world.buildStation(named: "Home", at: PlanPoint(x: 1_536, y: 1_536))
        try world.buildStation(named: "Foot", at: PlanPoint(x: 5_632, y: 1_536))
        let line = try world.createLine(named: "Main", stops: [home, foot]).id
        try world.assignTrain(try world.purchaseTrain(named: "T").id, to: line)
        try world.setStationDemand(home, to: StationDemand(kind: .residential, dailyTrips: 1_000))
        try world.setStationDemand(foot, to: StationDemand(kind: .scenic, dailyTrips: 0))
        world.setOutsideConnections(true)
        world.setTourism([Attraction(id: AttractionID(rawValue: 1), name: "x", englishName: "x",
                                     point: PlanPoint(x: 6_632, y: 1_536), kind: kind, baseStars: 300)])
        return world
    }

    func testAHarboursTouristsComeAtLunchAndLeaveAfterSunset() throws {
        let harbour = try world(.harbour), coast = try world(.coast)
        // Day 0, a Monday in January: 2,000 × 0.6 × 0.9 × 0.2 = 216; a beach's 0.5 is 120.
        XCTAssertEqual(harbour.dailyDemand(from: home, to: foot), 216)
        XCTAssertEqual(coast.dailyDemand(from: home, to: foot), 120)
        XCTAssertEqual(harbour.hourlyDemand(from: home, to: foot), GameWorld.apportion(216, by: Tourism.harbourArrivals))
        XCTAssertEqual(harbour.hourlyDemand(from: foot, to: home), GameWorld.apportion(216, by: Tourism.harbourDepartures))
        XCTAssertGreaterThan(harbour.hourlyDemand(from: foot, to: home)[19], coast.hourlyDemand(from: foot, to: home)[19])
    }

    func testThePlanReleasesItsHours() throws {
        let world = try world(.harbour)
        let plan = try XCTUnwrap(world.makePassengerPlan())
        for (index, flow) in plan.flows.enumerated() {
            XCTAssertEqual(Array(plan.hourly[index * 24..<(index + 1) * 24]), world.hourlyDemand(from: flow.origin, to: flow.destination))
        }
    }

    // MARK: - An old save's

    func testAnOldSavesCoastsTakeTheirKind() throws {
        var world = try world(.coast)
        let point = PlanPoint(x: 6_632, y: 1_536)
        world.setTourism([
            Attraction(id: AttractionID(rawValue: 1), name: "漁人碼頭", englishName: "Tamsui Fisherman's Wharf", point: point, kind: .coast, baseStars: 300),
            Attraction(id: AttractionID(rawValue: 2), name: "漁港碼頭", englishName: "Fishing Harbour", point: point, kind: .coast, baseStars: 300),
            Attraction(id: AttractionID(rawValue: 3), name: "野柳", englishName: "Yehliu", point: point, kind: .coast, baseStars: 350),
            Attraction(id: AttractionID(rawValue: 4), name: "港", englishName: "Nanfang'ao", point: point, kind: .town, baseStars: 300),
        ])
        world.reclassifyHarbours()
        XCTAssertEqual(world.tourism?.attractions.map(\.kind), [.harbour, .harbour, .coast, .town])
    }

    func testASaveOfVersion106IsReclassifiedWhenRead() throws {
        var world = try world(.coast)
        world.setTourism([Attraction(id: AttractionID(rawValue: 1), name: "南方澳", englishName: "Nanfang'ao",
                                     point: PlanPoint(x: 6_632, y: 1_536), kind: .coast, baseStars: 250)])
        let data = try JSONEncoder().encode(SavedGame(world: world))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 107)
        let current = try JSONDecoder().decode(SavedGame.self, from: data)
        XCTAssertEqual(current.world.tourism?.attractions.first?.kind, .coast, "a coast written by this build stays one")
        object["saveVersion"] = 106
        let old = try JSONDecoder().decode(SavedGame.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(old.world.tourism?.attractions.first?.kind, .harbour)
    }

    /// `v107-harbour-sights.json`: Home and Foot a minute in, with a
    /// harbour by Foot. Written once by the version 107 build
    /// (`HARBOUR_SAVE_NEW=1`).
    func testVersionOneHundredSevenKeepsTheHarbour() throws {
        var world = try world(.harbour)
        try world.advance(ticks: 1)
        let url = SavedGameTests.fixtures.appendingPathComponent("v107-harbour-sights.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["HARBOUR_SAVE_NEW"] != nil, SavedGame.currentVersion == 107 {
            try encoder.encode(SavedGame(world: world)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 107)
        var loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(loaded.tourism?.attractions.map(\.kind), [.harbour])
        XCTAssertEqual(loaded, world, "the save is the world this build makes the same way")
        try loaded.advance(ticks: 1_440)
        try world.advance(ticks: 1_440)
        XCTAssertEqual(loaded, world)
    }
}
