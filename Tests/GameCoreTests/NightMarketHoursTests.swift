import Foundation
@testable import GameCore
import XCTest

/// Night markets keep the evening's hours (decision 769): their tourists
/// arrive from about 17:00 and leave towards midnight, where a sight's come
/// before midday and leave in the afternoon. Every expectation is worked
/// out from the rules.
final class NightMarketHoursTests: XCTestCase {
    // MARK: - The hours

    /// `0.02 + g(h; μ, σ)` normalised to a day's mean of 1, in thousandths,
    /// rounded half up.
    private func curve(_ mu: Double, _ sigma: Double) -> [Int64] {
        let raw = (0..<24).map { 0.02 + exp(-0.5 * pow((Double($0) - mu) / sigma, 2)) }
        let mean = raw.reduce(0, +) / 24
        return raw.map { Int64(($0 / mean * 1_000).rounded()) }
    }

    func testTheTablesAreTheFormula() {
        XCTAssertEqual(Tourism.nightMarketArrivals, curve(19, 1.6))
        XCTAssertEqual(Tourism.nightMarketDepartures, curve(21.5, 1.4))
    }

    func testNineInTenRideBetweenFiveAndMidnight() {
        for table in [Tourism.nightMarketArrivals, Tourism.nightMarketDepartures] {
            let evening = table[17..<24].reduce(0, +), day = table.reduce(0, +)
            XCTAssertGreaterThanOrEqual(evening * 100, day * 87)
        }
        XCTAssertEqual(Tourism.nightMarketArrivals.firstIndex(of: Tourism.nightMarketArrivals.max()!), 19)
        XCTAssertEqual(Tourism.nightMarketDepartures.firstIndex(of: Tourism.nightMarketDepartures.max()!), 21)
    }

    func testANightMarketHasNoSeason() {
        for month in 1...12 { XCTAssertEqual(Tourism.seasonFactor(.nightMarket, month: month), 1_000) }
    }

    func testTheKindIsLastSoABlankMapDrawsTheSameKinds() {
        XCTAssertEqual(Array(AttractionKind.allCases.prefix(5)), [.coast, .mountain, .hotSpring, .town, .nightMarket])
        XCTAssertTrue(GameWorld.attractionNames[.town]!.contains { $0.english == GameWorld.blankNightMarketName })
        XCTAssertNil(GameWorld.attractionNames[.nightMarket])
    }

    // MARK: - A world

    private let home = StationID(rawValue: 1), foot = StationID(rawValue: 2)

    /// `TourismTests`' world: Home (residential) and Foot (scenic, no trips
    /// of its own) on line Main with a train, a 3-star sight of `kind`
    /// 15.6 m from Foot.
    private func world(_ kind: AttractionKind) throws -> GameWorld {
        var world = try GameWorld(bounds: WorldBounds(width: 12_288, height: 3_072), economy: fixtureEconomy(balance: 300_000_000, costs: testCosts))
        try world.buildStation(named: "Home", at: PlanPoint(x: 1_536, y: 1_536))
        try world.buildStation(named: "Foot", at: PlanPoint(x: 5_632, y: 1_536))
        let line = try world.createLine(named: "Main", stops: [home, foot]).id
        try world.assignTrain(try world.purchaseTrain(named: "T").id, to: line)
        try world.setStationDemand(home, to: StationDemand(kind: .residential, dailyTrips: 1_000))
        try world.setStationDemand(foot, to: StationDemand(kind: .scenic, dailyTrips: 0))
        world.setOutsideConnections(true)
        world.setTourism([Attraction(id: AttractionID(rawValue: 9), name: "夜市", englishName: "Night Market",
                                     point: PlanPoint(x: 6_632, y: 1_536), kind: kind, baseStars: 300)])
        return world
    }

    func testANightMarketsTouristsRideInTheEvening() throws {
        let world = try world(.nightMarket)
        // Day 0 is a Monday: 2,000 × 0.6 × 0.2 = 240, as a town's.
        XCTAssertEqual(world.dailyDemand(from: home, to: foot), 240)
        XCTAssertEqual(world.dailyDemand(from: foot, to: home), 240)
        XCTAssertEqual(world.hourlyDemand(from: home, to: foot), GameWorld.apportion(240, by: Tourism.nightMarketArrivals))
        XCTAssertEqual(world.hourlyDemand(from: foot, to: home), GameWorld.apportion(240, by: Tourism.nightMarketDepartures))
        let out = world.hourlyDemand(from: home, to: foot), back = world.hourlyDemand(from: foot, to: home)
        XCTAssertEqual(out[19], 55, "240 × 5,462 / 23,999")
        XCTAssertEqual(back[21], 62, "240 × 6,155 / 23,993")
        XCTAssertLessThanOrEqual(out[10], 1)
    }

    func testATownsTouristsKeepTheDaysHours() throws {
        let night = try world(.nightMarket), town = try world(.town)
        let townOut = town.hourlyDemand(from: home, to: foot), nightOut = night.hourlyDemand(from: home, to: foot)
        XCTAssertEqual(townOut.reduce(0, +), nightOut.reduce(0, +), "the same tourists")
        XCTAssertGreaterThan(townOut[10], nightOut[10])
        XCTAssertGreaterThan(nightOut[19], townOut[19])
    }

    func testThePlanReleasesTheEveningsHours() throws {
        let world = try world(.nightMarket)
        let plan = try XCTUnwrap(world.makePassengerPlan())
        for (index, flow) in plan.flows.enumerated() {
            XCTAssertEqual(Array(plan.hourly[index * 24..<(index + 1) * 24]), world.hourlyDemand(from: flow.origin, to: flow.destination))
        }
    }

    // MARK: - The company's night markets

    func testTheCompanysNightMarketIsANightMarketsSight() throws {
        var world = try GameWorld(bounds: WorldBounds(width: 131_072, height: 65_536), economy: fixtureEconomy(balance: 1_000_000_000_000, costs: testCosts))
        world.setEconomyMode(.management)
        world.setTourism([Attraction(id: AttractionID(rawValue: 1), name: "x", englishName: "x", point: PlanPoint(x: 120_000, y: 2_000), kind: .town, baseStars: 300)])
        let market = try world.placeBuilding(.nightMarket, at: PlanPoint(x: 31_000, y: 26_768))
        let temple = try world.placeBuilding(.temple, at: PlanPoint(x: 80_000, y: 26_768))
        let sights = Dictionary(uniqueKeysWithValues: world.companySights().map { ($0.building, $0.sight.kind) })
        XCTAssertEqual(sights[market.id], .nightMarket)
        XCTAssertEqual(sights[temple.id], .town)
    }

    // MARK: - A save from before

    func testAnOldSavesNightMarketsBecomeNightMarkets() throws {
        var world = try world(.town)
        world.setTourism([
            Attraction(id: AttractionID(rawValue: 1), name: "士林夜市", englishName: "Shilin Night Market", point: PlanPoint(x: 6_632, y: 1_536), kind: .town, baseStars: 300),
            Attraction(id: AttractionID(rawValue: 2), name: "老街", englishName: "Old Street", point: PlanPoint(x: 6_000, y: 1_536), kind: .town, baseStars: 300),
            Attraction(id: AttractionID(rawValue: 3), name: "海", englishName: "Night Market Beach", point: PlanPoint(x: 6_000, y: 1_000), kind: .coast, baseStars: 300),
        ])
        world.reclassifyNightMarkets()
        XCTAssertEqual(world.tourism?.attractions.map(\.kind), [.nightMarket, .town, .coast])
    }
}
