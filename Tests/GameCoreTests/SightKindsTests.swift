import Foundation
@testable import GameCore
import XCTest

/// Landmarks, museums and temples (decision 772): each its own season,
/// days and hours. Every expectation is worked out from the rules.
final class SightKindsTests: XCTestCase {
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
        XCTAssertEqual(Tourism.museumArrivals, curve { 0.01 + self.g($0, 11, 1.8) })
        XCTAssertEqual(Tourism.museumDepartures, curve { 0.01 + self.g($0, 15.5, 1.3) })
        XCTAssertEqual(Tourism.templeArrivals, curve { 0.02 + 0.6 * self.g($0, 8, 1.5) + 0.4 * self.g($0, 18.5, 1.5) })
        XCTAssertEqual(Tourism.templeDepartures, curve { 0.02 + 0.6 * self.g($0, 9.5, 1.5) + 0.4 * self.g($0, 20, 1.5) })
        XCTAssertEqual(Tourism.landmarkArrivals, curve { 0.02 + self.g($0, 14, 3.5) })
        XCTAssertEqual(Tourism.landmarkDepartures, curve { 0.02 + self.g($0, 17.5, 3) })
    }

    func testTheHoursFitTheKinds() {
        let museum = Tourism.museumDepartures, temple = Tourism.templeArrivals, landmark = Tourism.landmarkDepartures
        // Nearly nine in ten of a museum's leave between noon and 18:00, before it closes.
        XCTAssertGreaterThanOrEqual(museum[12..<18].reduce(0, +) * 100, museum.reduce(0, +) * 85)
        // A temple's first pilgrims by 8:00, and a second rush at dusk.
        XCTAssertEqual(temple.firstIndex(of: temple.max()!), 8)
        XCTAssertGreaterThan(temple[18], temple[13] * 10)
        // A landmark's leave until late, for the night view.
        XCTAssertGreaterThan(landmark[21], landmark[11])
        XCTAssertNil(Tourism.hours(of: .town))
        XCTAssertNil(Tourism.hours(of: .coast))
    }

    func testTheNewKindsAreLastSoABlankMapDrawsTheSameKinds() {
        XCTAssertEqual(Array(AttractionKind.allCases.prefix(8)), [.coast, .mountain, .hotSpring, .town, .nightMarket, .landmark, .museum, .temple])
        for (name, _) in GameWorld.blankSightKinds {
            XCTAssertTrue(GameWorld.attractionNames[.town]!.contains { $0.english == name }, name)
        }
    }

    // MARK: - Days and seasons

    func testAMuseumClosesOnMondaysThatAreNotHolidays() {
        XCTAssertEqual(Tourism.dayFactor(.museum, weekday: 1, holiday: nil, dayOfMonth: 3), 0)
        XCTAssertEqual(Tourism.dayFactor(.museum, weekday: 1, holiday: .newYear, dayOfMonth: 1), 2_000)
        XCTAssertEqual(Tourism.dayFactor(.museum, weekday: 2, holiday: nil, dayOfMonth: 3), 600)
        XCTAssertEqual(Tourism.dayFactor(.town, weekday: 1, holiday: nil, dayOfMonth: 3), 600)
    }

    func testATemplesFirstAndFifteenthAndSpringFestival() {
        XCTAssertEqual(Tourism.dayFactor(.temple, weekday: 2, holiday: nil, dayOfMonth: 2), 600)
        XCTAssertEqual(Tourism.dayFactor(.temple, weekday: 2, holiday: nil, dayOfMonth: 1), 900)
        XCTAssertEqual(Tourism.dayFactor(.temple, weekday: 6, holiday: nil, dayOfMonth: 15), 2_400)
        XCTAssertEqual(Tourism.dayFactor(.temple, weekday: 3, holiday: .springFestival, dayOfMonth: 20), 2_500)
        XCTAssertEqual(Tourism.dayFactor(.temple, weekday: 3, holiday: .springFestival, dayOfMonth: 1), 3_750)
        XCTAssertEqual(Tourism.dayFactor(.landmark, weekday: 3, holiday: .springFestival, dayOfMonth: 1), 2_000)
    }

    func testSeasonsAndRain() {
        XCTAssertEqual((1...12).map { Tourism.seasonFactor(.landmark, month: $0) },
                       [1_100, 1_100, 1_000, 1_000, 1_000, 1_000, 1_200, 1_200, 1_000, 1_000, 1_000, 1_000])
        XCTAssertEqual((1...12).map { Tourism.seasonFactor(.museum, month: $0) },
                       [1_000, 1_000, 1_000, 1_000, 1_000, 1_000, 1_200, 1_200, 1_000, 1_000, 1_000, 1_000])
        XCTAssertEqual((1...12).map { Tourism.seasonFactor(.temple, month: $0) },
                       [1_000, 1_000, 1_000, 1_300, 1_000, 1_000, 1_000, 1_000, 1_000, 1_000, 1_000, 1_000])
        XCTAssertEqual(Tourism.weatherFactor(.museum, clear: false), 1_100)
        XCTAssertEqual(Tourism.weatherFactor(.temple, clear: false), 700)
        XCTAssertEqual(Tourism.weatherFactor(.museum, clear: true), 1_000)
    }

    // MARK: - A world

    private let home = StationID(rawValue: 1), foot = StationID(rawValue: 2)

    /// `NightMarketHoursTests`' world: Home (residential) and Foot (scenic)
    /// on line Main with a train, a 3-star sight of `kind` 15.6 m from Foot.
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

    func testAMuseumIsEmptyOnDayZeroAMonday() throws {
        let world = try world(.museum)
        XCTAssertEqual(world.dailyDemand(from: home, to: foot), 0)
        // Tuesday: 2,000 × 0.6 × 0.2 = 240, as a town's.
        XCTAssertEqual(world.touristsExpected(at: AttractionID(rawValue: 1), onDay: 1), 240)
    }

    func testATemplesPilgrimsComeEarlyOnTheFirst() throws {
        let world = try world(.temple)
        // Day 0 is the first of the month and a Monday: 2,000 × 0.9 × 0.2 = 360.
        XCTAssertEqual(world.dailyDemand(from: home, to: foot), 360)
        XCTAssertEqual(world.hourlyDemand(from: home, to: foot), GameWorld.apportion(360, by: Tourism.templeArrivals))
        XCTAssertEqual(world.hourlyDemand(from: foot, to: home), GameWorld.apportion(360, by: Tourism.templeDepartures))
        XCTAssertEqual(world.touristsExpected(at: AttractionID(rawValue: 1), onDay: 1), 240, "the second: a weekday's")
    }

    func testALandmarksTouristsStayIntoTheEvening() throws {
        let landmark = try world(.landmark), town = try world(.town)
        // Day 0 is in January, the winter holidays: 2,000 × 0.6 × 1.1 × 0.2 = 264.
        XCTAssertEqual(landmark.dailyDemand(from: home, to: foot), 264)
        XCTAssertEqual(landmark.hourlyDemand(from: foot, to: home), GameWorld.apportion(264, by: Tourism.landmarkDepartures))
        XCTAssertGreaterThan(landmark.hourlyDemand(from: foot, to: home)[21], town.hourlyDemand(from: foot, to: home)[21])
    }

    func testThePlanReleasesTheirHours() throws {
        // A museum draws nobody on day 0, a Monday.
        for kind in [AttractionKind.landmark, .temple] {
            let world = try world(kind)
            let plan = try XCTUnwrap(world.makePassengerPlan())
            for (index, flow) in plan.flows.enumerated() {
                XCTAssertEqual(Array(plan.hourly[index * 24..<(index + 1) * 24]), world.hourlyDemand(from: flow.origin, to: flow.destination), "\(kind)")
            }
        }
    }

    // MARK: - The company's and an old save's

    func testTheCompanysTempleAndMuseumStayTowns() throws {
        var world = try GameWorld(bounds: WorldBounds(width: 131_072, height: 65_536), economy: fixtureEconomy(balance: 1_000_000_000_000, costs: testCosts))
        world.setEconomyMode(.management)
        world.setTourism([Attraction(id: AttractionID(rawValue: 1), name: "x", englishName: "x", point: PlanPoint(x: 120_000, y: 2_000), kind: .town, baseStars: 300)])
        let temple = try world.placeBuilding(.temple, at: PlanPoint(x: 80_000, y: 26_768))
        let museum = try world.placeBuilding(.railwayMuseum, at: PlanPoint(x: 31_000, y: 26_768))
        let sights = Dictionary(uniqueKeysWithValues: world.companySights().map { ($0.building, $0.sight.kind) })
        XCTAssertEqual(sights[temple.id], .town)
        XCTAssertEqual(sights[museum.id], .town)
    }

    func testAnOldSavesTownsTakeTheirKinds() throws {
        var world = try world(.town)
        let point = PlanPoint(x: 6_632, y: 1_536)
        world.setTourism([
            Attraction(id: AttractionID(rawValue: 1), name: "台北101", englishName: "Taipei 101", point: point, kind: .town, baseStars: 350),
            Attraction(id: AttractionID(rawValue: 2), name: "故宮", englishName: "National Palace Museum", point: point, kind: .town, baseStars: 350),
            Attraction(id: AttractionID(rawValue: 3), name: "龍山寺", englishName: "Lungshan Temple", point: point, kind: .town, baseStars: 300),
            Attraction(id: AttractionID(rawValue: 4), name: "媽祖廟", englishName: "Mazu Temple", point: point, kind: .town, baseStars: 300),
            Attraction(id: AttractionID(rawValue: 5), name: "老街", englishName: "Old Street", point: point, kind: .town, baseStars: 300),
            Attraction(id: AttractionID(rawValue: 6), name: "海", englishName: "Museum", point: point, kind: .coast, baseStars: 300),
        ])
        world.reclassifySightKinds()
        XCTAssertEqual(world.tourism?.attractions.map(\.kind), [.landmark, .museum, .temple, .temple, .town, .coast])
    }

    func testASaveOfVersion105IsReclassifiedWhenRead() throws {
        var world = try world(.town)
        world.setTourism([Attraction(id: AttractionID(rawValue: 1), name: "台北101", englishName: "Taipei 101",
                                     point: PlanPoint(x: 6_632, y: 1_536), kind: .town, baseStars: 350)])
        let data = try JSONEncoder().encode(SavedGame(world: world))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, SavedGame.currentVersion)
        let current = try JSONDecoder().decode(SavedGame.self, from: data)
        XCTAssertEqual(current.world.tourism?.attractions.first?.kind, .town, "a town written by this build stays one")
        object["saveVersion"] = 105
        let old = try JSONDecoder().decode(SavedGame.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(old.world.tourism?.attractions.first?.kind, .landmark)
    }

    /// `v106-sight-kinds.json`: Home and Foot a minute in, with a temple by
    /// Foot. Written once by the version 106 build (`SIGHT_KINDS_SAVE_NEW=1`).
    func testVersionOneHundredSixKeepsTheTemple() throws {
        var world = try world(.temple)
        try world.advance(ticks: 1)
        let url = SavedGameTests.fixtures.appendingPathComponent("v106-sight-kinds.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["SIGHT_KINDS_SAVE_NEW"] != nil, SavedGame.currentVersion == 106 {
            try encoder.encode(SavedGame(world: world)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 106)
        var loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(loaded.tourism?.attractions.map(\.kind), [.temple])
        XCTAssertEqual(loaded, world, "the save is the world this build makes the same way")
        try loaded.advance(ticks: 1_440)
        try world.advance(ticks: 1_440)
        XCTAssertEqual(loaded, world)
    }
}
