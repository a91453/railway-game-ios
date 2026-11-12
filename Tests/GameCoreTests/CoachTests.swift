import Foundation
@testable import GameCore
import XCTest

/// Decision 706: intercity coaches. The real coaches run by themselves;
/// a direct coach takes part of a pair's trips from the railway, and a
/// station by a coach stop takes the coach passengers the railway can
/// carry on. Every expectation is worked out by hand from the rules.
final class CoachTests: XCTestCase {
    private let home = StationID(rawValue: 1), foot = StationID(rawValue: 2)
    /// Within 800 m of Home and of Foot.
    private let byHome = PlanPoint(x: 10_000, y: 26_768), byFoot = PlanPoint(x: 900_000, y: 26_768)
    private let hours: [Int64] = (0..<24).map { (6..<22).contains($0) ? 1 : 0 }

    /// Home and Foot, 13.9 km apart, with a train in a managed company and
    /// no city: Home's 10,000 trips a day are its weight.
    private func world(line: Bool = true, footTrips: Int64 = 0) throws -> GameWorld {
        var world = try GameWorld(bounds: WorldBounds(width: 1_048_576, height: 65_536), economy: fixtureEconomy(balance: 1_000_000_000_000, costs: testCosts))
        world.setEconomyMode(.management)
        try world.buildStation(named: "Home", at: PlanPoint(x: 10_000, y: 32_768))
        try world.buildStation(named: "Foot", at: PlanPoint(x: 900_000, y: 32_768))
        if line {
            let line = try world.createLine(named: "Main", stops: [home, foot]).id
            try world.assignTrain(try world.purchaseTrain(named: "T").id, to: line)
        }
        try world.setStationDemand(home, to: StationDemand(kind: .residential, dailyTrips: 10_000))
        try world.setStationDemand(foot, to: StationDemand(kind: .civic, dailyTrips: footTrips))
        return world
    }

    /// A stop by Home with coaches to one by Foot, and that one.
    private func stops(coaches: Int64 = 96, minutes: Int64 = 20, fare: Int64 = 50, passengers: Int64 = 6_000) -> [CoachStop] {
        [
            CoachStop(id: 9, name: "家", point: byHome, dailyCoaches: coaches, dailyPassengers: passengers, hours: hours,
                      links: [CoachLink(to: 2, dailyCoaches: coaches, minutes: minutes, fare: fare)]),
            CoachStop(id: 9, name: "腳", point: byFoot, dailyCoaches: coaches, dailyPassengers: passengers, hours: hours),
        ]
    }

    func testTheRulesNumbers() {
        // Half the gap between 96 coaches over 16 hours; never over 30.
        XCTAssertEqual(CoachRules.waitMinutes(coaches: 96), 5)
        XCTAssertEqual(CoachRules.waitMinutes(coaches: 4), 30)
        XCTAssertEqual(CoachRules.waitMinutes(coaches: 0), 30)
        // Nothing while the train costs 700 thousandths of the coach or
        // less, the cap from 1,300, evenly between.
        XCTAssertEqual(CoachRules.share(rail: 70, coach: 100), 0)
        XCTAssertEqual(CoachRules.share(rail: 100, coach: 100), 125)
        XCTAssertEqual(CoachRules.share(rail: 130, coach: 100), 250)
        XCTAssertEqual(CoachRules.share(rail: 500, coach: 100), 250)
        XCTAssertEqual(CoachRules.share(rail: 85, coach: 100), 62)
        XCTAssertEqual(CoachRules.dayFactor(weekday: 1, holiday: false), 1_000)
        XCTAssertEqual(CoachRules.dayFactor(weekday: 5, holiday: false), 1_090)
        XCTAssertEqual(CoachRules.dayFactor(weekday: 6, holiday: false), 900)
        XCTAssertEqual(CoachRules.dayFactor(weekday: 0, holiday: false), 930)
        XCTAssertEqual(CoachRules.dayFactor(weekday: 2, holiday: true), 1_090)
        // 20 minutes, 5 waiting, NT$ 50 at 5 a minute.
        XCTAssertEqual(CoachLink(to: 2, dailyCoaches: 96, minutes: 20, fare: 50).cost, 35)
    }

    func testSettingStopsNumbersThemAndTheirLinks() throws {
        var world = try world()
        let off = CoachStop(id: 1, name: "外", point: PlanPoint(x: 2_000_000, y: 0), dailyCoaches: 5, dailyPassengers: 5, hours: hours,
                            links: [CoachLink(to: 2, dailyCoaches: 5, minutes: 5, fare: 5)])
        let list = [off] + stops().map {
            // The links count the list from 1: Foot's stop is its third.
            CoachStop(id: $0.id, name: $0.name, point: $0.point, dailyCoaches: $0.dailyCoaches, dailyPassengers: $0.dailyPassengers, hours: hours,
                      links: $0.links.map { CoachLink(to: $0.to + 1, dailyCoaches: $0.dailyCoaches, minutes: $0.minutes, fare: $0.fare) }
                        + [CoachLink(to: 1, dailyCoaches: 3, minutes: 3, fare: 3)])
        }
        world.setCoachStops(list)
        XCTAssertEqual(world.coachStops.map(\.id), [1, 2])
        XCTAssertEqual(world.coachStops[0].links, [CoachLink(to: 2, dailyCoaches: 96, minutes: 20, fare: 50)])
        XCTAssertEqual(world.coachStops[1].links, [], "the stop off the map is gone, and its links with it")
        XCTAssertNil(world.coachStopsProblem())
        let saved = try JSONDecoder().decode(SavedGame.self, from: try JSONEncoder().encode(SavedGame(world: world)))
        XCTAssertEqual(saved.world.coachStops, world.coachStops)
        world.setCoachStops([])
        XCTAssertEqual(world.coachStops, [])
    }

    func testAStationByAStopTakesItsPassengersBothWays() throws {
        var world = try world()
        XCTAssertEqual(world.dailyDemand(from: home, to: foot), 0, "Foot draws no one of its own")
        world.setCoachStops([stops()[1]])
        let day = try XCTUnwrap(world.coachDays().first)
        XCTAssertEqual(day.station, foot)
        // A Monday: 6,000 passengers, 200 riders a thousand, half each
        // way: 600 want the train; Home's 10,000 at one for 60 carries 166.
        XCTAssertEqual(day.passengers, 6_000)
        XCTAssertEqual(day.coaches, 96)
        XCTAssertEqual(day.ridersTo, 166)
        XCTAssertEqual(day.ridersFrom, 166)
        XCTAssertEqual(world.dailyDemand(from: home, to: foot), 166)
        XCTAssertEqual(world.dailyDemand(from: foot, to: home), 166)
        // On the hours the coaches call: none before 6 or from 22.
        let byHour = world.hourlyDemand(from: foot, to: home)
        XCTAssertEqual(byHour.reduce(0, +), 166)
        XCTAssertEqual(byHour[0..<6].reduce(0, +) + byHour[22...].reduce(0, +), 0)
        XCTAssertEqual(world.coachDays(at: foot).map(\.stop.id), [1])
        XCTAssertEqual(world.coachDays(at: home), [])
        XCTAssertEqual(world.coachStops(at: foot).map(\.name), ["腳"])
    }

    func testASmallStopSendsAllWhoWantTheTrain() throws {
        var world = try world()
        world.setCoachStops([CoachStop(id: 1, name: "腳", point: byFoot, dailyCoaches: 10, dailyPassengers: 240, hours: hours)])
        let day = try XCTUnwrap(world.coachDays().first)
        // 240 passengers, 200 a thousand, half each way.
        XCTAssertEqual(day.ridersFrom, 24)
        XCTAssertEqual(day.ridersTo, 24)
    }

    func testAStopWithNoStationSendsNoOne() throws {
        var world = try world(line: false)
        world.setCoachStops(stops())
        let day = try XCTUnwrap(world.coachDays().first)
        XCTAssertNil(day.station, "no train calls at Home")
        XCTAssertEqual(day.passengers, 6_000)
        XCTAssertEqual(day.riders, 0)
    }

    private static let track = TestLine(tiles: 140)

    /// A at column 1 and B at column 135 of one line with a train every
    /// 10 minutes, network routing: A to B rides 3 minutes and waits 5.
    /// Each has 10,000 trips a day, so A sends its 10,000 to B.
    private func corridor() throws -> GameWorld {
        var world = try makeWorld(width: 143 * TestLine.tile, height: 4 * TestLine.tile, balance: 100_000_000)
        try Self.track.build(in: &world)
        try Self.track.buildStation(named: "A", beside: 1, at: 2, in: &world)
        try Self.track.buildStation(named: "B", beside: 135, at: 2, in: &world)
        let line = try world.createLine(named: "Main", stops: [home, foot]).id
        try world.setLineServiceWindow(line, to: .allDay)
        try world.setLineTargetHeadways(line, to: TargetHeadways(peak: 10, offPeak: 10, low: 10))
        try world.assignTrain(try world.purchaseTrain(named: "T").id, to: line)
        try world.setStationDemand(home, to: StationDemand(kind: .residential, dailyTrips: 10_000))
        try world.setStationDemand(foot, to: StationDemand(kind: .office, dailyTrips: 10_000))
        world.setPassengerRoutingMode(.network)
        world.setSpeed(.normal)
        return world
    }

    /// A stop at A with coaches to one at B; 240 passengers each, of whom
    /// 24 ride the trains each way, all between A and B.
    private func corridorStops(_ world: GameWorld, coaches: Int64, minutes: Int64, fare: Int64) throws -> [CoachStop] {
        let from = try XCTUnwrap(world.stations.first { $0.id == home }).point, to = try XCTUnwrap(world.stations.first { $0.id == foot }).point
        return [
            CoachStop(id: 1, name: "家", point: from, dailyCoaches: coaches, dailyPassengers: 240, hours: hours,
                      links: [CoachLink(to: 2, dailyCoaches: coaches, minutes: minutes, fare: fare)]),
            CoachStop(id: 2, name: "腳", point: to, dailyCoaches: coaches, dailyPassengers: 240, hours: hours),
        ]
    }

    func testADirectCoachTakesPartOfThePairsTrips() throws {
        let plain = try corridor()
        XCTAssertEqual(plain.dailyDemand(from: home, to: foot), 10_000)
        XCTAssertEqual(try XCTUnwrap(plain.passengerRoutes(from: home, to: foot).map(\.totalMinutes).min()), 8)
        let fare = try XCTUnwrap(plain.tripFare(from: home, to: foot)).amount
        let rail = 8 + fare / CoachRules.moneyPerMinute
        // The stops' own riders: 24 from A's stop to B and 24 to B's from A.
        let own: Int64 = 48
        // A coach that costs twice the train takes no one.
        var dear = plain
        dear.setCoachStops(try corridorStops(plain, coaches: 960, minutes: 2 * rail, fare: 0))
        XCTAssertEqual(dear.coachRivals()[home]?[foot]?.cost, 2 * rail)
        XCTAssertEqual(dear.dailyDemand(from: home, to: foot), 10_000 + own)
        // One that costs the same takes half the cap, 125 a thousand.
        var even = plain
        even.setCoachStops(try corridorStops(plain, coaches: 960, minutes: rail, fare: 0))
        XCTAssertEqual(even.dailyDemand(from: home, to: foot), 10_000 - 1_250 + own)
        // The fare counts at NT$ 5 a minute, and the wait for a coach.
        var fared = plain
        fared.setCoachStops(try corridorStops(plain, coaches: 96, minutes: rail - 7, fare: 10))
        XCTAssertEqual(fared.dailyDemand(from: home, to: foot), 10_000 - 1_250 + own, "5 minutes waiting and 2 of fare")
        // One far cheaper takes the cap, 250 a thousand.
        var cheap = plain
        cheap.setCoachStops(try corridorStops(plain, coaches: 960, minutes: 1, fare: 0))
        XCTAssertEqual(cheap.dailyDemand(from: home, to: foot), 10_000 - 2_500 + own)
        // The other way has no coach.
        XCTAssertEqual(cheap.dailyDemand(from: foot, to: home), dear.dailyDemand(from: foot, to: home))
        // The plan the trains carry agrees: a day releases as many.
        try cheap.advance(ticks: 1_440)
        try dear.advance(ticks: 1_440)
        XCTAssertEqual(dear.passengerLedger(of: home).released - cheap.passengerLedger(of: home).released, 2_500)
    }

    func testMidnightCountsTheDayThatEnded() throws {
        var world = try world()
        world.setCoachStops(stops())
        world.setSpeed(.normal)
        try world.advance(ticks: 1_442)
        XCTAssertEqual(world.coachStops.map(\.yesterdayPassengers), [6_000, 6_000])
        // Home's stop has no one to ride to: Foot has no residents.
        XCTAssertEqual(world.coachStops.map(\.yesterdayRiders), [0, 332])
        // Set again, a stop keeps its counted day.
        world.setCoachStops(Array(stops().reversed().map {
            CoachStop(id: 1, name: $0.name, point: $0.point, dailyCoaches: 50, dailyPassengers: 500, hours: hours)
        }))
        XCTAssertEqual(world.coachStops.map(\.yesterdayRiders), [332, 0])
    }

    func testAWorldWithoutCoachStopsIsUnchanged() throws {
        var world = try world(footTrips: 10_000)
        world.setPassengerRoutingMode(.network)
        let data = try JSONEncoder().encode(SavedGame(world: world))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("coachStops"))
        XCTAssertEqual(world.coachDays(), [])
        XCTAssertEqual(world.coachRivals(), [:])
        // Stops no station stands by change no trip.
        var far = world
        far.setCoachStops(stops().map {
            CoachStop(id: 1, name: $0.name, point: PlanPoint(x: $0.point.x + 60_000, y: 1), dailyCoaches: 96, dailyPassengers: 6_000, hours: hours,
                      links: $0.links)
        })
        XCTAssertEqual(far.coachStops.count, 2)
        for (from, to) in [(home, foot), (foot, home)] {
            XCTAssertEqual(far.dailyDemand(from: from, to: to), world.dailyDemand(from: from, to: to))
            XCTAssertEqual(far.hourlyDemand(from: from, to: to), world.hourlyDemand(from: from, to: to))
        }
        world.setSpeed(.normal)
        try world.advance(ticks: 10)
    }

    func testAStopOutOfShapeIsRefused() throws {
        var world = try world()
        world.setCoachStops(stops())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let good = String(decoding: try encoder.encode(SavedGame(world: world)), as: UTF8.self)
        XCTAssertNoThrow(try JSONDecoder().decode(SavedGame.self, from: Data(good.utf8)))
        func refused(_ old: String, _ new: String, line: UInt = #line) {
            XCTAssertTrue(good.contains(old), old, line: line)
            let bad = good.replacingOccurrences(of: old, with: new)
            XCTAssertThrowsError(try JSONDecoder().decode(SavedGame.self, from: Data(bad.utf8)), new, line: line)
        }
        refused(#""links":[2,96,20,50]"#, #""links":[2,96,20]"#)
        refused(#""links":[2,96,20,50]"#, #""links":[3,96,20,50]"#)
        refused(#""links":[2,96,20,50]"#, #""links":[1,96,20,50]"#)
        refused(#""links":[2,96,20,50]"#, #""links":[2,0,20,50]"#)
        refused(#""dailyCoaches":96,"dailyPassengers":6000,"hours":[0,0,0,0,0,0,1"#, #""dailyCoaches":96,"dailyPassengers":6000,"hours":[0,0,0,0,0,1"#)
        refused(#""name":"家""#, #""name":"""#)
    }

    /// A version 91 save keeps the coach stops and their counted day.
    /// Written with `COACH_SAVE_NEW=1`, as the save was first made.
    func testTheSaveKeepsTheCoachStops() throws {
        var world = try world()
        world.setCoachStops(stops())
        world.setSpeed(.normal)
        try world.advance(ticks: 1_442)

        // The file is version 91's, whatever this build writes: never
        // written again under a later version's name.
        let url = SavedGameTests.fixtures.appendingPathComponent("v91-coach-stops.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["COACH_SAVE_NEW"] != nil, SavedGame.currentVersion == 91 {
            try encoder.encode(SavedGame(world: world)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"saveVersion\" : 91"), "the fixture is a version 91 save")
        var loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(loaded.coachStops.map(\.name), ["家", "腳"])
        XCTAssertEqual(loaded.coachStops[0].links, [CoachLink(to: 2, dailyCoaches: 96, minutes: 20, fare: 50)])
        XCTAssertEqual(loaded.coachStops.map(\.yesterdayRiders), [0, 332])
        // It runs on as the game it was saved from.
        try loaded.advance(ticks: 1_440)
        try world.advance(ticks: 1_440)
        XCTAssertEqual(loaded, world)
        XCTAssertEqual(try encoder.encode(SavedGame(world: loaded)), try encoder.encode(SavedGame(world: world)))
    }
}
