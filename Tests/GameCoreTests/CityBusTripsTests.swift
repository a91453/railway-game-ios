import Foundation
@testable import GameCore
import XCTest

/// City bus routes (decision 438): a route with no station of its own
/// carries the trips between its stops' land, gives way to walking on
/// short trips and to scooters on slow ones, takes no one from the trains,
/// feeds a station it passes and carries no more than its buses hold.
/// Every expectation is worked out by hand from the rules; a cell is 4,096
/// units (64 m).
final class CityBusTripsTests: XCTestCase {
    private static let track = TestLine(tiles: 256, row: 33)
    private let cell = Land.cellLength
    private let a = StationID(rawValue: 1)
    private let b = StationID(rawValue: 2)

    private func at(_ column: Int) -> CellPosition {
        CellPosition(row: 8, column: column)
    }

    /// A managed world of 128 × 16 cells (8,192 × 1,024 m) with land
    /// demand: A in cell (8, 5) with 1,000 residents and B in cell (8, 60)
    /// with 1,000 office jobs, 3,520 m apart on a line with a train; a road
    /// all along row 8; and `land` beside. A minute a tick.
    private func world(_ land: [LandCell], balance: Money = 1_000_000_000) throws -> GameWorld {
        var world = GameWorld(bounds: try WorldBounds(width: 128 * cell, height: 16 * cell), economy: GameEconomy(balance: balance, costs: testCosts))
        try Self.track.build(in: &world)
        try Self.track.buildStation(named: "A", beside: 21, at: 33, in: &world)
        try Self.track.buildStation(named: "B", beside: 241, at: 33, in: &world)
        world.setEconomyMode(.management)
        try world.setLand([LandCell(row: 8, column: 5, use: .residential, residents: 1_000, jobs: 0),
                           LandCell(row: 8, column: 60, use: .office, residents: 0, jobs: 1_000)] + land)
        world.setLandDemand(true)
        world.enableRoads()
        try world.setRoads((0..<128).map(at), in: (0..<8).map { LandBlock(row: 0, column: $0) })
        let line = try world.createLine(named: "Main", stops: [a, b]).id
        try world.setLineServiceWindow(line, to: .allDay)
        try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        let train = try world.purchaseTrain(named: "T").id
        try world.placeTrain(train, at: Self.track.at(21, facingEast: true))
        try world.setTrainMovementRate(train, to: 1_024)
        try world.assignTrain(train, to: line)
        world.setPassengerRoutingMode(.network)
        world.setSpeed(.normal)
        return world
    }

    private func homes(_ column: Int, _ residents: Int64) -> LandCell {
        LandCell(row: 8, column: column, use: .residential, residents: residents, jobs: 0)
    }

    private func offices(_ column: Int, _ jobs: Int64) -> LandCell {
        LandCell(row: 8, column: column, use: .office, residents: 0, jobs: jobs)
    }

    private func trips(_ world: GameWorld, _ station: StationID) -> Int64? {
        world.passengers.first { $0.station == station }?.demand?.dailyTrips
    }

    // MARK: - The town's own trips

    /// Homes by (8, 30) and offices by (8, 100), 4,480 m apart: each
    /// stop's 400 people make 40 trips a day, a quarter of a station's
    /// share, all to the other stop. The route runs 4,480 m: 40 minutes
    /// a round trip, so four buses keep 10; the trip is no walk, a wait
    /// of 5 and a ride of 15.
    func testACityRouteCarriesTheTownsOwnTrips() throws {
        var world = try world([homes(30, 400), offices(100, 400)])
        let before = (trips(world, a), trips(world, b))
        let route = try world.createBusRoute(to: nil, stops: [at(30), at(100)], service: .every(minutes: 10), buses: 4)
        XCTAssertNil(route.station)
        XCTAssertEqual(route.legMetres, [4_480], "a leg from each stop to the next, none past the last")
        XCTAssertEqual(route.headway, 10)
        let carried = try XCTUnwrap(world.busRoute(id: route.id))
        XCTAssertEqual(carried.localTrips, 80)
        XCTAssertEqual(carried.localMinutes, 20)
        XCTAssertEqual(carried.feederTrips, 0)
        XCTAssertNil(carried.transfer, "no stop within 400 m of a station")
        XCTAssertEqual(trips(world, a), before.0, "the trains lose no one")
        XCTAssertEqual(trips(world, b), before.1)

        // A day: 80 riders at $5; 144 departures, 1,290.24 km there and
        // back at $20.
        try world.advance(ticks: 1_440 + 30)
        let day = try XCTUnwrap(world.busRoute(id: route.id)?.days.last)
        XCTAssertEqual(day.riders, 80)
        XCTAssertEqual(day.fares, Money(80 * 500))
        XCTAssertEqual(day.cost, Money(2_580_480))
        XCTAssertTrue(world.accounts.entries.allSatisfy(GameWorld.isWellFormed))

        // With no bus the route carries no one.
        try world.setBusCount(route.id, to: 0)
        XCTAssertEqual(world.busRoute(id: route.id)?.localTrips, 0)
        XCTAssertEqual(world.busRoute(id: route.id)?.localMinutes, 0)
    }

    /// Stops 0, 1 and 2 by (8, 30) with 400 residents, (8, 46) with 300
    /// jobs and (8, 90) with 100: 40, 30 and 10 trips, each stop's to the
    /// others by their people, the largest remainder last (stop 2's 10 go
    /// 5.71 and 4.29, 6 and 4). Stops 0 and 1 are 1,024 m apart, so their
    /// trips keep 414‰ (12 of 30, 9 of 24); the rest are 2 km and more.
    func testTripsGoWhereThePeopleAreAndShortOnesWalk() throws {
        var world = try world([homes(30, 400), offices(46, 300), offices(90, 100)])
        let route = try world.createBusRoute(to: nil, stops: [at(30), at(46), at(90)], service: .every(minutes: 10), buses: 4)
        XCTAssertEqual(world.busRoute(id: route.id)?.localTrips, 12 + 10 + 9 + 6 + 6 + 4)
    }

    /// The simple rule: the bus's 20 minutes door to door against a
    /// scooter's 16 over the 4,480 m (5,824 m of road): 1250‰, half the
    /// 250 over is 125‰, 5 of each stop's 40.
    func testScootersTakeSomeOfASlowRoutesTrips() throws {
        var world = try world([homes(30, 400), offices(100, 400)])
        try world.setModeShift(.simple)
        let route = try world.createBusRoute(to: nil, stops: [at(30), at(100)], service: .every(minutes: 10), buses: 4)
        XCTAssertEqual(world.busRoute(id: route.id)?.localTrips, 70)
    }

    /// One bus a day there and back holds 140: the other 660 of the 800
    /// trips stay home.
    func testABusCarriesNoMoreThanItHolds() throws {
        var world = try world([homes(30, 4_000), offices(100, 4_000)])
        let route = try world.createBusRoute(to: nil, stops: [at(30), at(100)], service: .runs([360]), buses: 1)
        XCTAssertEqual(world.busRoute(id: route.id)?.localTrips, 800)
        XCTAssertEqual(world.busRoute(id: route.id)?.dailyDepartures, 1)
        try world.advance(ticks: 1_440 + 30)
        XCTAssertEqual(world.busRoute(id: route.id)?.days.last?.riders, 2 * BusRoute.capacity)
        XCTAssertEqual(BusRoute.capacity, 70)
    }

    // MARK: - Transfers

    /// The second stop, (8, 64), is 264 m from B: the route feeds B. The
    /// homes by the first stop ride half as much as B's own land, 80 trips
    /// more for B, as a feeder's.
    func testACityRoutePassingAStationFeedsIt() throws {
        var world = try world([homes(30, 400)])
        XCTAssertEqual(trips(world, b), 400)
        let route = try world.createBusRoute(to: nil, stops: [at(30), at(64)], service: .every(minutes: 10), buses: 4)
        let fed = try XCTUnwrap(world.busRoute(id: route.id))
        XCTAssertEqual(fed.transfer, BusTransfer(station: b, stop: 1))
        XCTAssertEqual(fed.feederTrips, 80)
        XCTAssertGreaterThan(fed.feederMinutes, 0)
        XCTAssertEqual(fed.localTrips, 0, "no one lives by the other stop")
        XCTAssertEqual(trips(world, b), 480)
        XCTAssertEqual(trips(world, a), 400)

        // Riders at B count on the bus.
        try world.advance(ticks: 1_440 + 30)
        XCTAssertGreaterThan(try XCTUnwrap(world.busRoute(id: route.id)?.days.last).riders, 0)

        // Without B the route runs on, feeding no one.
        try world.removeLine(world.lines[0].id)
        try world.removeStation(b)
        XCTAssertEqual(world.busRoutes.map(\.id), [route.id])
        XCTAssertNil(world.busRoute(id: route.id)?.transfer)
        XCTAssertEqual(world.busRoute(id: route.id)?.feederTrips, 0)
    }

    // MARK: - Refused

    func testACityRouteHasTwoStopsAtLeast() throws {
        var world = try world([])
        let before = world
        XCTAssertThrowsGameError(try world.createBusRoute(to: nil, stops: [at(30)], service: .every(minutes: 10), buses: 1), .invalidBusRoute)
        // A leg each stop but the last.
        XCTAssertThrowsGameError(try world.createBusRoute(to: nil, stops: [at(30), at(40)], legMetres: [640, 640], service: .every(minutes: 10), buses: 1),
                                 .invalidBusRoute)
        XCTAssertEqual(world, before)
        let route = try world.createBusRoute(to: nil, stops: [at(30), at(40)], legMetres: [700], service: .every(minutes: 10), buses: 1)
        XCTAssertEqual(route.legMetres, [700])
        XCTAssertThrowsGameError(try world.setBusRouteStops(route.id, stops: [at(30)]), .invalidBusRoute)
    }

    // MARK: - Saves

    /// Decision 438's save: a city route between the homes and the offices,
    /// a city route through B, a feeder to A and the player's roads, run a
    /// day.
    func testVersionSeventyFiveKeepsCityRoutesAndThePlayersRoads() throws {
        var world = try world([homes(30, 400), offices(100, 400), homes(20, 200)])
        try world.createBusRoute(to: nil, stops: [at(30), at(100)], service: .every(minutes: 10), buses: 4)
        try world.createBusRoute(to: nil, stops: [at(30), at(64)], service: .every(minutes: 15), buses: 2)
        try world.createBusRoute(to: a, stops: [at(20)], service: .every(minutes: 20), buses: 1)
        try world.buildRoad(along: [at(40), CellPosition(row: 7, column: 41), CellPosition(row: 6, column: 41)])
        try world.advance(ticks: 1_440 + 30)

        let url = SavedGameTests.fixtures.appendingPathComponent("v75-city-bus-roads.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["CITY_BUS_SAVE_NEW"] != nil {
            try encoder.encode(SavedGame(world: world)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 75)
        let loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(loaded, world)
        XCTAssertEqual(loaded.busRoutes.map(\.station), [nil, nil, a])
        XCTAssertEqual(loaded.busRoutes.map(\.transfer), [nil, BusTransfer(station: b, stop: 1), nil])
        XCTAssertEqual(loaded.roads?.built, [CellPosition(row: 7, column: 41), CellPosition(row: 6, column: 41)])
        XCTAssertEqual(try encoder.encode(SavedGame(world: loaded)), data)

        // Version 74 had no city routes: a route there names its station.
        var old = object
        var saved = try XCTUnwrap(old["world"] as? [String: Any])
        var routes = try XCTUnwrap(saved["busRoutes"] as? [[String: Any]])
        routes = routes.filter { $0["station"] != nil }
        saved["busRoutes"] = routes
        var roads = try XCTUnwrap(saved["roads"] as? [String: Any])
        roads["built"] = nil
        saved["roads"] = roads
        old["world"] = saved
        old["saveVersion"] = 74
        let feeders = try JSONDecoder().decode(SavedGame.self, from: JSONSerialization.data(withJSONObject: old)).world
        XCTAssertEqual(feeders.busRoutes.map(\.station), [a])
        XCTAssertEqual(feeders.roads?.built, [])
    }

    func testDamagedCityRoutesAreRefused() throws {
        var world = try world([homes(30, 400)])
        try world.createBusRoute(to: nil, stops: [at(30), at(64)], service: .every(minutes: 10), buses: 4)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(SavedGame(world: world))) as? [String: Any])
        let saved = try XCTUnwrap(object["world"] as? [String: Any])
        let route = try XCTUnwrap((saved["busRoutes"] as? [[String: Any]])?.first)
        func load(_ change: (inout [String: Any]) -> Void) throws {
            var plain = object, world = saved, bus = route
            change(&bus)
            world["busRoutes"] = [bus]
            plain["world"] = world
            _ = try JSONDecoder().decode(SavedGame.self, from: JSONSerialization.data(withJSONObject: plain))
        }
        XCTAssertNoThrow(try load { _ in })
        XCTAssertThrowsError(try load { $0["stops"] = [["row": 8, "column": 30]]; $0["legMetres"] = [] }, "a city route of one stop")
        XCTAssertThrowsError(try load { $0["legMetres"] = [100, 100] }, "a leg past the last stop")
        XCTAssertThrowsError(try load { $0["transfer"] = ["station": 9, "stop": 1] }, "a transfer to a station the world has not")
        XCTAssertThrowsError(try load { $0["transfer"] = ["station": 2, "stop": 2] }, "a transfer at a stop the route has not")
        XCTAssertThrowsError(try load { $0["localTrips"] = -1 }, "trips below none")
        XCTAssertThrowsError(try load { $0["localMinutes"] = 1_441 }, "more than a day")
    }
}
