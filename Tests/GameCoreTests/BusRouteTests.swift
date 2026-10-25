import Foundation
@testable import GameCore
import XCTest

/// The company's buses feeding its stations (decision 400, 10i-2): the
/// route's lengths and headway, the land a stop brings in, the mode shift's
/// bus end, the fares and running costs, the commands and the save. Every
/// expectation is worked out by hand from the rules; a cell is 4,096 units
/// (64 m).
final class BusRouteTests: XCTestCase {
    private static let track = TestLine(tiles: 256, row: 33)
    private let cell = Land.cellLength
    private let a = StationID(rawValue: 1)
    private let b = StationID(rawValue: 2)
    private let stop = CellPosition(row: 8, column: 26)

    /// A managed world of 64 × 16 cells (4,096 × 1,024 m) with land
    /// demand: A beside tile 21, in cell (8, 5), and B beside tile 241, in
    /// cell (8, 60), 220 tiles (3,520 m) apart on a line with a train.
    /// A's cell has 1,000 residents and B's 1,000 office jobs; cells (8, 24) to (8, 28), 1,224 m and more from A, out of its
    /// 800 m, 200 residents each. A road runs along row 8 from column 5
    /// to 30. A minute a tick.
    private func world(balance: Money = 1_000_000_000) throws -> GameWorld {
        var world = GameWorld(bounds: try WorldBounds(width: 64 * cell, height: 16 * cell), economy: GameEconomy(balance: balance, costs: testCosts))
        try Self.track.build(in: &world)
        try Self.track.buildStation(named: "A", beside: 21, at: 33, in: &world)
        try Self.track.buildStation(named: "B", beside: 241, at: 33, in: &world)
        world.setEconomyMode(.management)
        try world.setLand([LandCell(row: 8, column: 5, use: .residential, residents: 1_000, jobs: 0)]
            + (24...28).map { LandCell(row: 8, column: $0, use: .residential, residents: 200, jobs: 0) }
            + [LandCell(row: 8, column: 60, use: .office, residents: 0, jobs: 1_000)])
        world.setLandDemand(true)
        world.enableRoads()
        try world.setRoads((5...30).map { CellPosition(row: 8, column: $0) }, in: [LandBlock(row: 0, column: 0), LandBlock(row: 0, column: 1)])
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

    private func trips(_ world: GameWorld, _ station: StationID) -> Int64? {
        world.passengers.first { $0.station == station }?.demand?.dailyTrips
    }

    // MARK: - The route

    func testARoutesHeadwayIsNoCloserThanItsBusesCanKeep() {
        // 1,344 m: there and back 8.96 minutes, up to 9, and 10 at the
        // ends: 19 minutes a round trip.
        var route = BusRoute(id: BusRouteID(rawValue: 1), station: a, stops: [stop], legMetres: [1_344], service: .every(minutes: 10), buses: 2)
        XCTAssertEqual(route.roundTripMinutes, 19)
        XCTAssertEqual(route.headway, 10, "two buses keep 10 minutes (19 / 2, up)")
        route.buses = 1
        XCTAssertEqual(route.headway, 19, "one bus every round trip")
        route.buses = 0
        XCTAssertNil(route.headway, "no bus, no route")
        route.buses = 3
        XCTAssertEqual(route.headway, 10, "as set")
        // Runs at 6:00, 6:20, 7:05: 65 minutes in two gaps, 32.5 up to 33.
        route.service = .runs([360, 380, 425])
        XCTAssertEqual(route.headway, 33)
        route.service = .runs([360])
        XCTAssertEqual(route.headway, 1_440, "one run a day")
        XCTAssertEqual(route.rideMinutes(fromStop: 0), 4, "1,344 m at 18 km/h, 4.48 minutes")
        // The walk: 1.25 times the straight line at 75 m a minute.
        XCTAssertEqual(BusRoute.walkMinutes(units: 0), 0)
        XCTAssertEqual(BusRoute.walkMinutes(units: 4_096), 1, "64 m, 80 m on foot")
        XCTAssertEqual(BusRoute.walkMinutes(units: 8_192), 2, "128 m, 160 m on foot")
        XCTAssertEqual(BusRoute.walkMinutes(units: 25_600), 7, "400 m, 500 m on foot, 6.67")
    }

    func testADrawnRouteTakesTheShortestWayAlongTheRoads() throws {
        var world = try world()
        // Along row 8 from (8, 26) to A's cell (8, 5): 21 cells.
        XCTAssertEqual(world.busRoadMetres(from: stop, to: CellPosition(row: 8, column: 5)), 1_344)
        // A side road up from (8, 20) to (5, 23): corner to corner three
        // times, 270 m, then along row 8, 15 × 64 m.
        try world.setRoads([CellPosition(row: 7, column: 21), CellPosition(row: 6, column: 22), CellPosition(row: 5, column: 23)],
                           in: [LandBlock(row: 0, column: 0), LandBlock(row: 0, column: 1)])
        XCTAssertEqual(world.busRoadMetres(from: CellPosition(row: 5, column: 23), to: CellPosition(row: 8, column: 5)), 270 + 15 * 64)
        XCTAssertNil(world.busRoadMetres(from: stop, to: CellPosition(row: 2, column: 2)), "no road there")
        let route = try world.createBusRoute(to: a, stops: [CellPosition(row: 5, column: 23), stop], service: .every(minutes: 15), buses: 1)
        // From (5, 23) down to (7, 21) and corner to corner on to (8, 22):
        // three corners and four cells along to the stop.
        XCTAssertEqual(route.legMetres, [270 + 4 * 64, 1_344], "the first stop to the second, the second to A")
    }

    // MARK: - The feeder

    /// The stop at (8, 26) reaches the five cells (400 m is 6.25 cells):
    /// 1,000 residents, riding half as much as A's own (500 people), 200
    /// trips, A's 400 its own. Their minutes: the walk 2, 1, 0, 1, 2, half
    /// the headway 5 and the ride 4, 10.2 on average.
    func testAStopBringsInTheLandNoStationReaches() throws {
        var world = try world()
        XCTAssertEqual(trips(world, a), 400)
        XCTAssertEqual(trips(world, b), 400)
        let route = try world.createBusRoute(to: a, stops: [stop], service: .every(minutes: 10), buses: 2)
        XCTAssertEqual(route.id, BusRouteID(rawValue: 1))
        XCTAssertEqual(route.legMetres, [1_344])
        XCTAssertEqual(world.busRoute(id: route.id)?.feederTrips, 200)
        XCTAssertEqual(world.busRoute(id: route.id)?.feederMinutes, 10)
        XCTAssertEqual(trips(world, a), 600)
        XCTAssertEqual(trips(world, b), 400)

        // No bus: the land is out of reach again.
        try world.setBusCount(route.id, to: 0)
        XCTAssertEqual(world.busRoute(id: route.id)?.feederTrips, 0)
        XCTAssertEqual(trips(world, a), 400)
        // One bus: a bus every 19 minutes, a wait of 10.
        try world.setBusCount(route.id, to: 1)
        XCTAssertEqual(world.busRoute(id: route.id)?.feederMinutes, 15)
        try world.removeBusRoute(route.id)
        XCTAssertEqual(trips(world, a), 400)
        XCTAssertTrue(world.busRoutes.isEmpty)
    }

    func testTheLandAStationReachesOnFootStaysItsOwn() throws {
        var world = try world()
        // A stop at (8, 12), 7 cells (448 m) from A: it reaches (8, 6) to
        // (8, 18), all within A's 800 m, and the cells from 24 on are past
        // its 400 m.
        let route = try world.createBusRoute(to: a, stops: [CellPosition(row: 8, column: 12)], service: .every(minutes: 10), buses: 2)
        XCTAssertEqual(world.busRoute(id: route.id)?.feederTrips, 0)
        XCTAssertEqual(trips(world, a), 400)
    }

    /// 3,520 m: the road's 4,576 m take a scooter 9 + 4 = 13 minutes. A
    /// trip of 5 minutes on the train is 5 + 6 = 11 on foot, no slower;
    /// by bus, 5 + 3 + 10 = 18, 1384‰: the simple rule's half of 384 is
    /// 192‰, and 64 of the bus's 333 (200 of A's 600) switch.
    func testTheBusEndCountsInTheModeShift() throws {
        var world = try world()
        try world.setModeShift(.simple)
        XCTAssertEqual(world.modeShiftKept(1_000, from: a, to: b, minutes: 5), 1_000)
        try world.createBusRoute(to: a, stops: [stop], service: .every(minutes: 10), buses: 2)
        XCTAssertEqual(world.modeShiftKept(1_000, from: a, to: b, minutes: 5), 936)
        XCTAssertEqual(world.modeShiftKept(1_000, from: b, to: a, minutes: 5), 1_000, "B has no buses")
    }

    // MARK: - Money

    func testStopsAndBusesArePaidFor() throws {
        var world = try world()
        let before = world.economy.balance
        let route = try world.createBusRoute(to: a, stops: [stop], service: .every(minutes: 10), buses: 2)
        XCTAssertEqual(world.economy.balance, before - Money(1_000_000 + 2 * 5_000_000))
        try world.setBusCount(route.id, to: 3)
        XCTAssertEqual(world.economy.balance, before - Money(1_000_000 + 3 * 5_000_000))
        try world.setBusCount(route.id, to: 1)
        try world.setBusRouteStops(route.id, stops: [CellPosition(row: 8, column: 28), stop])
        XCTAssertEqual(world.economy.balance, before - Money(2 * 1_000_000 + 3 * 5_000_000), "one stop more; buses sold for nothing")
        XCTAssertEqual(world.busRoute(id: route.id)?.legMetres, [128, 1_344])
    }

    /// A day: the bus's share of A's riders setting out by train pay $5
    /// each. The 1,344 m route takes 9 + 10 minutes there and back, so
    /// two buses keep its 10 minutes: 144 departures, 387.072 km there and
    /// back at $20, $7,741.44.
    func testADaysBusesAreBookedTogether() throws {
        var world = try world()
        let route = try world.createBusRoute(to: a, stops: [stop], service: .every(minutes: 10), buses: 2)
        try world.advance(ticks: 1_440 + 30)
        let entry = try XCTUnwrap(world.accounts.entries.last { $0.kind == .dailyBuses })
        let day = try XCTUnwrap(world.busRoute(id: route.id)?.days.last)
        XCTAssertGreaterThan(day.riders, 0)
        XCTAssertEqual(day.fares, Money(day.riders * 500))
        XCTAssertEqual(day.cost, Money(774_144))
        XCTAssertEqual(entry.breakdown, [LedgerLine(item: .busFares, amount: day.fares), LedgerLine(item: .busRunning, amount: Money(-774_144))])
        XCTAssertTrue(world.accounts.entries.allSatisfy(GameWorld.isWellFormed))
    }

    /// Those whose train journey ends at A take the bus home too: on the
    /// line of two stations everyone who gets off at A arrives, so the
    /// bus carries its share (200 of A's 600 trips) of those boarding and
    /// those alighting there, give or take the thousandths carried over.
    func testRidersTakeTheBusHomeFromTheTrain() throws {
        var world = try world()
        world.setLineAccounts(true)
        let route = try world.createBusRoute(to: a, stops: [stop], service: .every(minutes: 10), buses: 2)
        try world.advance(ticks: 1_440 + 1_380)
        let day = world.dayIndex(of: world.clock.now)
        let flow = try XCTUnwrap(world.lineAccounts?.flows.first { $0.station == a && $0.day == day })
        XCTAssertGreaterThan(flow.alighted, 0)
        let riders = try XCTUnwrap(world.busRoute(id: route.id)).ridersToday
        XCTAssertEqual(Double(riders), Double((flow.boarded + flow.alighted) * 200) / 600, accuracy: 2)
    }

    /// A route's cost follows the kilometres its buses run: runs as many as
    /// its buses keep, and nothing with no bus.
    func testARouteCostsWhatItsBusesRun() throws {
        var world = try world()
        let route = try world.createBusRoute(to: a, stops: [stop], service: .runs([360, 420, 480]), buses: 1)
        // Three runs of 2.688 km there and back at $20: $161.28.
        XCTAssertEqual(world.busRoute(id: route.id)?.dailyDepartures, 3)
        XCTAssertEqual(world.busRoute(id: route.id)?.dailyCost, Money(16_128))
        // Every 60 minutes: 24 departures, $1,290.24.
        try world.setBusRuns(route.id, to: .every(minutes: 60))
        XCTAssertEqual(world.busRoute(id: route.id)?.dailyCost, Money(129_024))
        // Every minute, but one bus keeps a bus every 19 minutes: 75.
        try world.setBusRuns(route.id, to: .every(minutes: 1))
        XCTAssertEqual(world.busRoute(id: route.id)?.dailyDepartures, 75)
        try world.setBusCount(route.id, to: 0)
        XCTAssertEqual(world.busRoute(id: route.id)?.dailyCost, .zero)
    }

    // MARK: - Refused

    func testABadRouteIsRefusedAndChangesNothing() throws {
        var plain = try makeWorld()
        XCTAssertThrowsGameError(try plain.createBusRoute(to: a, stops: [stop], service: .every(minutes: 10), buses: 1), .roadsNotEnabled)
        var world = try world()
        try world.setRoads([CellPosition(row: 3, column: 3)], in: [LandBlock(row: 0, column: 0)])
        let before = world
        XCTAssertThrowsGameError(try world.createBusRoute(to: StationID(rawValue: 9), stops: [stop], service: .every(minutes: 10), buses: 1),
                                 .unknownStation(StationID(rawValue: 9)))
        XCTAssertThrowsGameError(try world.createBusRoute(to: a, stops: [], service: .every(minutes: 10), buses: 1), .invalidBusRoute)
        XCTAssertThrowsGameError(try world.createBusRoute(to: a, stops: [stop], service: .every(minutes: 0), buses: 1), .invalidBusRoute)
        XCTAssertThrowsGameError(try world.createBusRoute(to: a, stops: [stop], service: .runs([60, 60]), buses: 1), .invalidBusRoute)
        XCTAssertThrowsGameError(try world.createBusRoute(to: a, stops: [stop], service: .every(minutes: 10), buses: 100), .invalidBusRoute)
        XCTAssertThrowsGameError(try world.createBusRoute(to: a, stops: [stop], legMetres: [1, 2], service: .every(minutes: 10), buses: 1),
                                 .invalidBusRoute)
        XCTAssertThrowsGameError(try world.createBusRoute(to: a, stops: [CellPosition(row: 9, column: 26)], service: .every(minutes: 10), buses: 1),
                                 .busStopOffRoad)
        XCTAssertThrowsGameError(try world.createBusRoute(to: b, stops: [stop], service: .every(minutes: 10), buses: 1), .busStopOffRoad)
        XCTAssertThrowsGameError(try world.createBusRoute(to: a, stops: [CellPosition(row: 3, column: 3), stop], service: .every(minutes: 10), buses: 1),
                                 .busStopsNotConnected(leg: 0))
        var poor = try self.world(balance: Money(500_000))
        XCTAssertThrowsGameError(try poor.createBusRoute(to: a, stops: [stop], service: .every(minutes: 10), buses: 1),
                                 .insufficientFunds(required: Money(6_000_000), available: poor.economy.balance))
        XCTAssertTrue(poor.busRoutes.isEmpty)
        XCTAssertEqual(world, before)
        XCTAssertThrowsGameError(try world.setBusCount(BusRouteID(rawValue: 1), to: 1), .unknownBusRoute(BusRouteID(rawValue: 1)))
        XCTAssertThrowsGameError(try world.removeBusRoute(BusRouteID(rawValue: 1)), .unknownBusRoute(BusRouteID(rawValue: 1)))
    }

    func testRemovingTheStationClosesItsRoutes() throws {
        var world = try world()
        try world.createBusRoute(to: a, stops: [stop], service: .every(minutes: 10), buses: 2)
        try world.removeLine(world.lines[0].id)
        try world.removeStation(a)
        XCTAssertTrue(world.busRoutes.isEmpty)
        XCTAssertEqual(world.nextBusRouteID, 2)
    }

    // MARK: - Buying a real route

    func testARealRouteIsBoughtWithItsRealLengths() throws {
        var world = try world()
        // The app's real route: a motorway stretch makes its leg longer
        // than the roads' 1,344 m.
        let route = try world.createBusRoute(to: a, stops: [stop], legMetres: [2_100], service: .runs([360, 390, 420]), buses: 2)
        XCTAssertEqual(route.legMetres, [2_100])
        let before = world.economy.balance
        try world.recordBusAcquisition(route: route.id, realRoute: "bus:Taipei:307", dailyRiders: 3)
        XCTAssertEqual(world.economy.balance, before - Money(3_000_000))
        let bought = try XCTUnwrap(world.acquisition(of: "bus:Taipei:307"))
        XCTAssertEqual(bought.kind, .bus)
        XCTAssertEqual(bought.busRoute, route.id)
        XCTAssertNil(bought.line)
        XCTAssertThrowsGameError(try world.recordBusAcquisition(route: route.id, realRoute: "bus:Taipei:308", dailyRiders: 1), .lineAlreadyAcquired)
        XCTAssertThrowsGameError(try world.recordBusAcquisition(route: route.id, realRoute: "", dailyRiders: 1), .lineAlreadyAcquired)
        let other = try world.createBusRoute(to: a, stops: [stop], service: .every(minutes: 30), buses: 1)
        XCTAssertThrowsGameError(try world.recordBusAcquisition(route: other.id, realRoute: "", dailyRiders: 1), .invalidAcquisition)
        XCTAssertThrowsGameError(try world.recordBusAcquisition(route: other.id, realRoute: "bus:Taipei:307", dailyRiders: 1), .lineAlreadyAcquired)
        XCTAssertThrowsGameError(try world.recordBusAcquisition(route: BusRouteID(rawValue: 9), realRoute: "bus:x", dailyRiders: 1),
                                 .unknownBusRoute(BusRouteID(rawValue: 9)))
        // A railway's purchase is written as before, with no kind.
        let railway = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(LineAcquisition(realLine: "tra:PINGXI", line: LineID(rawValue: 1), day: 2, value: Money(100)))) as? [String: Any])
        XCTAssertEqual(Set(railway.keys), ["realLine", "line", "day", "value"])
        let bus = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(bought)) as? [String: Any])
        XCTAssertEqual(Set(bus.keys), ["kind", "realLine", "busRoute", "day", "value"])
        XCTAssertThrowsError(try JSONDecoder().decode(LineAcquisition.self, from: Data(#"{"kind":"bus","realLine":"x","line":1,"day":0,"value":0}"#.utf8)))
    }

    // MARK: - Saves

    func testVersionSeventyThreeKeepsTheBusRoute() throws {
        var world = try world()
        let route = try world.createBusRoute(to: a, stops: [stop], service: .every(minutes: 10), buses: 2)
        try world.createBusRoute(to: a, stops: [CellPosition(row: 8, column: 28), stop], legMetres: [128, 1_400], service: .runs([360, 420]), buses: 1)
        try world.recordBusAcquisition(route: route.id, realRoute: "bus:Taipei:307", dailyRiders: 3)
        try world.advance(ticks: 1_440 + 30)

        let url = SavedGameTests.fixtures.appendingPathComponent("v73-bus-route.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["BUS_ROUTE_SAVE_NEW"] != nil {
            try encoder.encode(SavedGame(world: world)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 73)
        let loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        // The routes as built; their day's figures are the save's, worked
        // out under the rules of version 73's day (decision 400's balance
        // has since halved the stops' land and costs a route by the
        // kilometre), and are not worked out again on loading.
        XCTAssertEqual(loaded.busRoutes.map(\.id), [BusRouteID(rawValue: 1), BusRouteID(rawValue: 2)])
        XCTAssertEqual(loaded.busRoutes.map(\.stops), world.busRoutes.map(\.stops))
        XCTAssertEqual(loaded.busRoutes.map(\.legMetres), world.busRoutes.map(\.legMetres))
        XCTAssertEqual(loaded.busRoutes.map(\.service), world.busRoutes.map(\.service))
        XCTAssertEqual(loaded.busRoutes.map(\.buses), world.busRoutes.map(\.buses))
        // The second route's first stop is nearest (8, 28): the first keeps
        // the four cells 24 to 27 (27 a tie, to the lower route), 320 trips
        // in the save, 160 now.
        XCTAssertEqual(loaded.busRoutes.map(\.feederTrips), [320, 80])
        XCTAssertEqual(world.busRoutes.map(\.feederTrips), [160, 40])
        XCTAssertEqual(loaded.acquisition(of: "bus:Taipei:307")?.kind, .bus)
        XCTAssertEqual(try encoder.encode(SavedGame(world: loaded)), Data(String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #""saveVersion" : 73,"#, with: #""saveVersion" : \#(SavedGame.currentVersion),"#).utf8))

        // Without the keys there are no buses.
        var plain = object
        var saved = try XCTUnwrap(plain["world"] as? [String: Any])
        saved["busRoutes"] = nil
        saved["nextBusRouteID"] = nil
        saved["acquisitions"] = nil
        plain["world"] = saved
        let off = try JSONDecoder().decode(SavedGame.self, from: JSONSerialization.data(withJSONObject: plain)).world
        XCTAssertTrue(off.busRoutes.isEmpty)
        XCTAssertEqual(off.nextBusRouteID, 1)
    }

    func testTheLongestRouteIsSavedAndLoaded() throws {
        // Two 200 km legs and one run a day: half a day's wait and over 1,300
        // minutes' ride from the far stop, more than a day door to door,
        // counted as a day so the save it writes loads.
        var world = try world()
        let route = try world.createBusRoute(to: a, stops: [stop, CellPosition(row: 8, column: 28)],
                                             legMetres: [BusRoute.maximumLegMetres, BusRoute.maximumLegMetres], service: .runs([360]), buses: 1)
        XCTAssertGreaterThan(try XCTUnwrap(world.busRoute(id: route.id)).feederTrips, 0)
        XCTAssertEqual(world.busRoute(id: route.id)?.feederMinutes, GameTime.minutesPerDay)
        let loaded = try JSONDecoder().decode(SavedGame.self, from: JSONEncoder().encode(SavedGame(world: world))).world
        XCTAssertEqual(loaded, world)
    }

    func testTheRouteNumbersRunOutWithoutACrash() throws {
        var world = try world()
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(SavedGame(world: world))) as? [String: Any])
        func load(_ next: Int) throws -> GameWorld {
            var plain = object, saved = try XCTUnwrap(object["world"] as? [String: Any])
            saved["nextBusRouteID"] = next
            plain["world"] = saved
            return try JSONDecoder().decode(SavedGame.self, from: JSONSerialization.data(withJSONObject: plain)).world
        }
        XCTAssertThrowsError(try load(0), "a counter below 1")
        XCTAssertThrowsError(try load(-5), "a counter below 1")
        world = try load(Int.max)
        let before = world
        XCTAssertThrowsGameError(try world.createBusRoute(to: a, stops: [stop], service: .every(minutes: 10), buses: 2), .idsExhausted)
        XCTAssertEqual(world, before)
    }

    func testABadServiceIsRefusedBeforeTheRoadsAreSearched() throws {
        var world = try world()
        let off = CellPosition(row: 2, column: 2)
        XCTAssertThrowsGameError(try world.createBusRoute(to: a, stops: [off], service: .every(minutes: 0), buses: 1), .invalidBusRoute)
        XCTAssertThrowsGameError(try world.createBusRoute(to: a, stops: [off], service: .every(minutes: 10), buses: 100), .invalidBusRoute)
        XCTAssertThrowsGameError(try world.createBusRoute(to: a, stops: [off], service: .every(minutes: 10), buses: 1), .busStopOffRoad)
    }

    func testDamagedBusRoutesAreRefused() throws {
        var world = try world()
        try world.createBusRoute(to: a, stops: [stop], service: .every(minutes: 10), buses: 2)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(SavedGame(world: world))) as? [String: Any])
        let saved = try XCTUnwrap(object["world"] as? [String: Any])
        let route = try XCTUnwrap((saved["busRoutes"] as? [[String: Any]])?.first)
        func load(_ change: (inout [String: Any], inout [String: Any]) -> Void) throws {
            var plain = object, world = saved, bus = route
            change(&world, &bus)
            world["busRoutes"] = [bus]
            plain["world"] = world
            _ = try JSONDecoder().decode(SavedGame.self, from: JSONSerialization.data(withJSONObject: plain))
        }
        XCTAssertNoThrow(try load { _, _ in })
        XCTAssertThrowsError(try load { _, bus in bus["station"] = 9 }, "a station the world has not")
        XCTAssertThrowsError(try load { world, _ in world["nextBusRouteID"] = 1 }, "a number not handed out")
        XCTAssertThrowsError(try load { _, bus in bus["legMetres"] = [1, 2] }, "a leg a stop")
        XCTAssertThrowsError(try load { _, bus in bus["stops"] = [["row": 16, "column": 0]]; bus["legMetres"] = [0] }, "a stop outside the world")
        XCTAssertThrowsError(try load { _, bus in bus["stops"] = Array(repeating: ["row": 0, "column": 0], count: 65) }, "too many stops")
        XCTAssertThrowsError(try load { _, bus in bus["buses"] = 100 }, "too many buses")
        XCTAssertThrowsError(try load { _, bus in bus["service"] = ["every": 10, "runs": [1]] }, "a headway and runs")
        XCTAssertThrowsError(try load { world, _ in world["roads"] = nil }, "buses without roads")
    }
}
