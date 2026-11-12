import Foundation
@testable import GameCore
import XCTest

/// Decision 695: airports as hubs. Flights come and go by themselves; a
/// station by the terminal takes the air passengers the railway can carry.
/// Every expectation is worked out by hand from the rules.
final class AirportTests: XCTestCase {
    private let home = StationID(rawValue: 1), foot = StationID(rawValue: 2)
    /// Within 800 m of Foot.
    private let terminal = PlanPoint(x: 31_000, y: 26_768)

    /// Home and Foot with a train in a managed company, no city and no
    /// tourism: Home's 10,000 trips a day are its weight.
    private func world(line: Bool = true) throws -> GameWorld {
        var world = try GameWorld(bounds: WorldBounds(width: 131_072, height: 65_536), economy: fixtureEconomy(balance: 1_000_000_000_000, costs: testCosts))
        world.setEconomyMode(.management)
        try world.buildStation(named: "Home", at: PlanPoint(x: 10_000, y: 32_768))
        try world.buildStation(named: "Foot", at: PlanPoint(x: 30_000, y: 32_768))
        if line {
            let line = try world.createLine(named: "Main", stops: [home, foot]).id
            try world.assignTrain(try world.purchaseTrain(named: "T").id, to: line)
        }
        try world.setStationDemand(home, to: StationDemand(kind: .residential, dailyTrips: 10_000))
        try world.setStationDemand(foot, to: StationDemand(kind: .civic, dailyTrips: 0))
        return world
    }

    private func airport(passengers: Int64 = 16_000, flights: Int64 = 150, first: Int = 0, last: Int = 24) -> Airport {
        Airport(id: 7, name: "機場", englishName: "Airport", point: terminal, dailyPassengers: passengers, dailyFlights: flights,
                firstHour: first, lastHour: last)
    }

    func testSettingAirportsNumbersThemAndLeavesOutThoseOffTheMap() throws {
        var world = try world()
        let off = Airport(id: 1, name: "外", englishName: "Off", point: PlanPoint(x: 200_000, y: 0), dailyPassengers: 1, dailyFlights: 1)
        let empty = Airport(id: 1, name: "空", englishName: "Empty", point: terminal, dailyPassengers: 0, dailyFlights: 1)
        world.setAirports([off, empty, airport()])
        XCTAssertEqual(world.airports.map(\.id), [1])
        XCTAssertEqual(world.airports.first?.name, "機場")
        XCTAssertNoThrow(try JSONDecoder().decode(SavedGame.self, from: try JSONEncoder().encode(SavedGame(world: world))))
        world.setAirports([])
        XCTAssertEqual(world.airports, [])
    }

    func testAnAirportWithNoStationHasFlightsAndNoRiders() throws {
        var world = try world(line: false)
        world.setAirports([airport()])
        let day = try XCTUnwrap(world.airportDays().first)
        XCTAssertNil(day.station, "no train calls at Foot")
        // A Monday: 950 thousandths of 150 flights and 16,000 passengers.
        XCTAssertEqual(day.flights, 142)
        XCTAssertEqual(day.passengers, 15_200)
        XCTAssertEqual(day.riders, 0)
        XCTAssertEqual(day.landings.reduce(0, +) + day.takeOffs.reduce(0, +), 142)
        XCTAssertEqual(world.dailyDemand(from: home, to: foot), 0)
    }

    func testAStationByTheTerminalTakesItsPassengersBothWays() throws {
        var world = try world()
        XCTAssertEqual(world.dailyDemand(from: home, to: foot), 0, "Foot draws no one of its own")
        world.setAirports([airport()])
        let day = try XCTUnwrap(world.airportDays().first)
        XCTAssertEqual(day.station, foot)
        // 15,200 passengers, 150 riders a thousand, half each way: 1,140 want
        // the train; Home's 10,000 at one for 60 carries 166.
        XCTAssertEqual(day.ridersAtMost, 1_140)
        XCTAssertEqual(day.ridersTo, 166)
        XCTAssertEqual(day.ridersFrom, 166)
        // 332 of 2,280 on board: 29 thousandths more flights and passengers.
        XCTAssertEqual(day.flights, 142 * 1_029 / 1_000)
        XCTAssertEqual(day.passengers, 15_200 * 1_029 / 1_000)
        XCTAssertEqual(world.dailyDemand(from: home, to: foot), 166)
        XCTAssertEqual(world.dailyDemand(from: foot, to: home), 166)
        XCTAssertEqual(world.hourlyDemand(from: home, to: foot).reduce(0, +), 166)
        XCTAssertEqual(world.airportDays(at: foot).map(\.airport.id), [1])
        XCTAssertEqual(world.airportDays(at: home), [])
    }

    func testABiggerCityFillsTheAirportsShare() throws {
        var world = try world()
        try world.setStationDemand(home, to: StationDemand(kind: .residential, dailyTrips: 90_000))
        world.setAirports([airport()])
        let day = try XCTUnwrap(world.airportDays().first)
        XCTAssertEqual(day.ridersTo, 1_140, "all who want the train")
        XCTAssertEqual(day.flights, 142 * 1_200 / 1_000, "a fifth more flights")
    }

    func testTheDaysFactor() {
        XCTAssertEqual(AirportRules.dayFactor(weekday: 1, holiday: false), 950)
        XCTAssertEqual(AirportRules.dayFactor(weekday: 5, holiday: false), 1_100)
        XCTAssertEqual(AirportRules.dayFactor(weekday: 6, holiday: false), 1_000)
        XCTAssertEqual(AirportRules.dayFactor(weekday: 0, holiday: false), 1_100)
        XCTAssertEqual(AirportRules.dayFactor(weekday: 2, holiday: true), 1_150)
    }

    func testACurfewKeepsFlightsAndRidersToItsHours() throws {
        var world = try world()
        world.setAirports([airport(first: 6, last: 23)])
        let day = try XCTUnwrap(world.airportDays().first)
        XCTAssertEqual(day.landings[0..<6].reduce(0, +), 0)
        XCTAssertEqual(day.landings[23], 0)
        XCTAssertEqual(day.takeOffs[0..<6].reduce(0, +), 0)
        XCTAssertGreaterThan(day.landings[8], 0)
        // To the airport two hours before the flights: none after 21:00,
        // the first at 04:00; from it an hour after: none before 07:00.
        let to = world.hourlyDemand(from: home, to: foot), from = world.hourlyDemand(from: foot, to: home)
        XCTAssertEqual(to[21...23].reduce(0, +), 0)
        XCTAssertEqual(to[0..<4].reduce(0, +), 0)
        XCTAssertGreaterThan(to[4], 0)
        XCTAssertEqual(from[1..<7].reduce(0, +), 0)
        XCTAssertGreaterThan(from[7], 0)
    }

    func testMidnightCountsTheDayThatEnded() throws {
        var world = try world()
        world.setAirports([airport()])
        world.setSpeed(.normal)
        try world.advance(ticks: 1_442)
        let counted = try XCTUnwrap(world.airports.first)
        XCTAssertEqual(counted.yesterdayRiders, 332)
        XCTAssertEqual(counted.yesterdayFlights, 146)
        XCTAssertEqual(counted.yesterdayPassengers, 15_640)
        XCTAssertNoThrow(try JSONDecoder().decode(SavedGame.self, from: try JSONEncoder().encode(SavedGame(world: world))))
    }

    func testTheAirPassengersSetOut() throws {
        var world = try world()
        world.setAirports([airport()])
        world.setSpeed(.normal)
        try world.advance(ticks: 1_440)
        // Home's only trips are those to the airport, Foot's those who
        // landed. (This world's train has no track, so they wait.)
        XCTAssertEqual(world.passengerLedger(of: home).released, 166)
        XCTAssertEqual(world.passengerLedger(of: foot).released, 166)
    }

    func testAWorldWithoutAirportsIsUnchanged() throws {
        var world = try world()
        let data = try JSONEncoder().encode(SavedGame(world: world))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("airports"))
        world.setSpeed(.normal)
        try world.advance(ticks: 10)
        XCTAssertEqual(world.airportDays(), [])
    }

    /// A version 90 save keeps the airports and their counted day. Written
    /// with `AIRPORT_SAVE_NEW=1`, as the save was first made.
    func testTheSaveKeepsTheAirports() throws {
        var world = try world()
        world.setAirports([airport(first: 6, last: 23)])
        world.setSpeed(.normal)
        try world.advance(ticks: 1_442)

        let url = SavedGameTests.fixtures.appendingPathComponent("v\(SavedGame.currentVersion)-airports.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["AIRPORT_SAVE_NEW"] != nil {
            try encoder.encode(SavedGame(world: world)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        var loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        let kept = try XCTUnwrap(loaded.airports.first)
        XCTAssertEqual(kept.name, "機場")
        XCTAssertEqual(kept.firstHour, 6)
        XCTAssertEqual(kept.lastHour, 23)
        XCTAssertEqual(kept.yesterdayRiders, 332)
        XCTAssertEqual(kept.yesterdayFlights, 146)
        // It runs on as the game it was saved from.
        try loaded.advance(ticks: 1_440)
        try world.advance(ticks: 1_440)
        XCTAssertEqual(loaded, world)
        XCTAssertEqual(try encoder.encode(SavedGame(world: loaded)), try encoder.encode(SavedGame(world: world)))
    }

    // MARK: - Decision 700: destinations

    /// Three passengers in four fly to the island, at six flights in seven.
    private let island = AirDestination(name: "離島", englishName: "Island", isDomestic: true, yearlyPassengers: 3_000_000, yearlyFlights: 30_000)
    private let abroad = AirDestination(name: "外國", englishName: "Abroad", isDomestic: false, yearlyPassengers: 1_000_000, yearlyFlights: 5_000)

    private func airportWithDestinations(first: Int = 6, last: Int = 23) -> Airport {
        Airport(id: 1, name: "機場", englishName: "Airport", point: terminal, dailyPassengers: 16_000, dailyFlights: 150,
                firstHour: first, lastHour: last, destinations: [island, abroad])
    }

    func testTheDestinationsSplitTheDay() throws {
        var world = try world()
        world.setAirports([airportWithDestinations()])
        let day = try XCTUnwrap(world.airportDays().first)
        XCTAssertEqual(day.airport.domesticShare, 750)
        // The totals are those of an airport with no destinations.
        XCTAssertEqual(day.ridersTo, 166)
        XCTAssertEqual(day.flights, 146)
        XCTAssertEqual(day.passengers, 15_640)
        XCTAssertEqual(day.domesticPassengers, 11_730)
        XCTAssertEqual(day.internationalPassengers, 3_910)
        // 73 take-offs at 6 to 1, 15,640 passengers at 3 to 1.
        XCTAssertEqual(day.departures.map(\.flights), [63, 10])
        XCTAssertEqual(day.departures.map(\.passengers), [11_730, 3_910])
        XCTAssertEqual(day.departures.map(\.destination), [island, abroad])
    }

    func testDomesticRidersKeepTheirOwnHours() throws {
        var world = try world()
        world.setAirports([airportWithDestinations()])
        // Flights from 06:00 to 23:00. To the airport: the international
        // riders two hours before (04:00 to 20:00), the domestic ones one
        // hour before (05:00 to 21:00). From it: an hour after landing
        // (07:00 to 23:00) and within the hour (06:00 to 22:00).
        let to = world.hourlyDemand(from: home, to: foot), from = world.hourlyDemand(from: foot, to: home)
        XCTAssertEqual(to.reduce(0, +), 166)
        XCTAssertEqual(from.reduce(0, +), 166)
        XCTAssertEqual(to[0..<4].reduce(0, +), 0)
        XCTAssertGreaterThan(to[4], 0)
        XCTAssertGreaterThan(to[21], 0, "a domestic rider for the 22:00 flights")
        XCTAssertEqual(to[22...23].reduce(0, +), 0)
        XCTAssertEqual(from[0..<6].reduce(0, +), 0)
        XCTAssertGreaterThan(from[6], 0, "off a domestic flight within the hour")
        XCTAssertGreaterThan(from[23], 0)
        // 124 of the 166 are domestic: 04:00 has only the other 42's share.
        var plain = try self.world()
        plain.setAirports([airport(first: 6, last: 23)])
        XCTAssertLessThan(to[4], plain.hourlyDemand(from: home, to: foot)[4])
        XCTAssertEqual(plain.hourlyDemand(from: home, to: foot)[21], 0)
    }

    func testTheSaveKeepsTheDestinations() throws {
        var world = try world()
        world.setAirports([airportWithDestinations()])
        let data = try JSONEncoder().encode(SavedGame(world: world))
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("\"destinations\""))
        XCTAssertEqual(try JSONDecoder().decode(SavedGame.self, from: data).world, world)
        // An airport with none writes nothing new.
        var plain = try self.world()
        plain.setAirports([airport()])
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(SavedGame(world: plain)), as: UTF8.self).contains("destinations"))
        // A destination with no passengers is refused.
        let broken = text.replacingOccurrences(of: "\"passengers\":3000000", with: "\"passengers\":0")
        XCTAssertNotEqual(broken, text)
        XCTAssertThrowsError(try JSONDecoder().decode(SavedGame.self, from: Data(broken.utf8)))
    }

    func testSettingAirportsAgainKeepsYesterdaysCount() throws {
        var world = try world()
        world.setAirports([airport()])
        world.setSpeed(.normal)
        try world.advance(ticks: 1_442)
        XCTAssertEqual(world.airports.first?.yesterdayRiders, 332)
        // The same airport with its destinations: the count stays.
        let many = (0..<30).map { AirDestination(name: "地 \($0)", englishName: "Place \($0)", isDomestic: $0 < 3, yearlyPassengers: 1_000, yearlyFlights: 10) }
            + [AirDestination(name: "空", englishName: "Empty", isDomestic: true, yearlyPassengers: 0, yearlyFlights: 10)]
        world.setAirports([Airport(id: 1, name: "機場", englishName: "Airport", point: terminal, dailyPassengers: 16_000, dailyFlights: 150, destinations: many)])
        let kept = try XCTUnwrap(world.airports.first)
        XCTAssertEqual(kept.yesterdayRiders, 332)
        XCTAssertEqual(kept.yesterdayFlights, 146)
        XCTAssertEqual(kept.destinations.count, AirportRules.maximumDestinations)
        XCTAssertNoThrow(try JSONDecoder().decode(SavedGame.self, from: try JSONEncoder().encode(SavedGame(world: world))))
        // Another airport starts with no day counted.
        world.setAirports([Airport(id: 1, name: "新機場", englishName: "New", point: terminal, dailyPassengers: 16_000, dailyFlights: 150)])
        XCTAssertEqual(world.airports.first?.yesterdayRiders, 0)
    }

    func testASaveWithABrokenAirportIsRefused() throws {
        var world = try world()
        world.setAirports([airport()])
        let data = try JSONEncoder().encode(SavedGame(world: world))
        let text = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\"dailyFlights\":150", with: "\"dailyFlights\":0")
        XCTAssertThrowsError(try JSONDecoder().decode(SavedGame.self, from: Data(text.utf8)))
    }
}
