import Foundation
@testable import GameCore
import XCTest

/// The company's cableways (decision 574): the spans, ride and capacity,
/// the land a stop brings in and the trips between its stops, the days it
/// stands still, the fares and running costs, the commands and the save.
/// Every expectation is worked out by hand from the rules; a cell is 4,096
/// units (64 m).
final class CablewayTests: XCTestCase {
    private static let track = TestLine(tiles: 256, row: 33)
    private let cell = Land.cellLength
    private let a = StationID(rawValue: 1)
    private let b = StationID(rawValue: 2)
    /// By A, an angle station up the hill, and out among the five cells of
    /// 200 residents: two spans of 689 m (10 cells across, 4 down).
    private let line = [
        CablewayStop(cell: CellPosition(row: 8, column: 6)),
        CablewayStop(cell: CellPosition(row: 4, column: 16), boards: false),
        CablewayStop(cell: CellPosition(row: 8, column: 26)),
    ]

    /// BusRouteTests' world without its roads: a managed world of 64 × 16
    /// cells with land demand, A beside tile 21 (cell (8, 5)) and B beside
    /// tile 241, a train between them; A's cell has 1,000 residents, B's
    /// 1,000 office jobs, cells (8, 24) to (8, 28), out of A's 800 m, 200
    /// residents each. A minute a tick.
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
        let route = try world.createLine(named: "Main", stops: [a, b]).id
        try world.setLineServiceWindow(route, to: .allDay)
        try world.setLineTrainsInService(route, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        let train = try world.purchaseTrain(named: "T").id
        try world.placeTrain(train, at: Self.track.at(21, facingEast: true))
        try world.setTrainMovementRate(train, to: 1_024)
        try world.assignTrain(train, to: route)
        world.setPassengerRoutingMode(.network)
        world.setSpeed(.normal)
        return world
    }

    private func trips(_ world: GameWorld, _ station: StationID) -> Int64? {
        world.passengers.first { $0.station == station }?.demand?.dailyTrips
    }

    // MARK: - The rope

    /// The Maokong Gondola: 4,033 m through six stops (two of them angle
    /// stations) at 5 m/s, 806.6 s up to 807, and 60 s through each of the
    /// four between: 1,047 s, 17.45 minutes, 17. Cabins of 8 every 12 s:
    /// 2,400 an hour each way, 12 hours on a weekday and 13 on a weekend.
    func testTheRideAndTheCabinsAreMaokongs() {
        let stops = (0..<6).map { CablewayStop(cell: CellPosition(row: 0, column: $0), boards: $0 % 2 == 0 || $0 == 5) }
        let maokong = Cableway(id: CablewayID(rawValue: 1), stops: stops, legMetres: [700, 700, 900, 900, 833])
        XCTAssertEqual(maokong.metres, 4_033)
        XCTAssertEqual(maokong.rideSeconds(from: 0, to: 5), 1_047)
        XCTAssertEqual(maokong.rideMinutes(from: 0, to: 5), 17)
        XCTAssertEqual(maokong.rideSeconds(from: 5, to: 0), 1_047, "the same both ways")
        XCTAssertEqual(maokong.rideSeconds(from: 0, to: 1), 140, "no stop between")
        XCTAssertEqual(Cableway.hourlyCapacity, 2_400)
        XCTAssertEqual(Cableway.dailyCapacity(onDay: 1), 57_600, "day 1 is a Tuesday: 12 hours both ways")
        XCTAssertEqual(Cableway.dailyCapacity(onDay: 5), 62_400, "day 5 is a Saturday: 13 hours")
        XCTAssertEqual(maokong.dailyCost, Money(4_033 * 500), "NT$5 a metre a day")
        // Four stations at NT$600,000, two angle stations at NT$200,000,
        // 4,033 m at NT$1,500.
        XCTAssertEqual(Cableway.price(of: stops, metres: 4_033), Money(4 * 60_000_000 + 2 * 20_000_000 + 4_033 * 150_000))
        XCTAssertTrue(maokong.isValid)
    }

    // MARK: - The land it draws

    /// The far stop at (8, 26) reaches the five cells: 1,000 residents,
    /// riding half as much as A's own (500 people), 200 trips, to A, which
    /// the first stop meets. The near stop's land is A's on foot. Their
    /// minutes: the walk 2, 1, 0, 1, 2, a minute's wait, the ride 336 s
    /// (1,378 m and the angle station) up to 6, and a minute's walk from
    /// the first stop to A: 9.2 on average.
    func testAStopBringsInTheLandNoStationReaches() throws {
        var world = try world()
        XCTAssertEqual(trips(world, a), 400)
        let balance = world.economy.balance
        let built = try world.createCableway(stops: line)
        XCTAssertEqual(built.id, CablewayID(rawValue: 1))
        XCTAssertEqual(built.legMetres, [689, 689])
        let cableway = try XCTUnwrap(world.cableway(id: built.id))
        XCTAssertEqual(cableway.transfer, BusTransfer(station: a, stop: 0))
        XCTAssertEqual(cableway.feederTrips, 200)
        XCTAssertEqual(cableway.feederMinutes, 9)
        XCTAssertEqual(cableway.localTrips, 0, "only the far stop has people of its own")
        XCTAssertEqual(trips(world, a), 600)
        XCTAssertEqual(trips(world, b), 400)
        // Two stations, an angle station and 1,378 m of rope.
        XCTAssertEqual(world.economy.balance, Money(balance.amount - 2 * 60_000_000 - 20_000_000 - 1_378 * 150_000))
        try world.removeCableway(built.id)
        XCTAssertNil(world.cableway(id: built.id))
        XCTAssertEqual(trips(world, a), 400)
    }

    /// The cableway takes its land first: a bus stop on the same cell
    /// brings in nothing more.
    func testABusStopDrawsNoneOfACablewaysLand() throws {
        var world = try world()
        world.enableRoads()
        try world.setRoads((5...30).map { CellPosition(row: 8, column: $0) }, in: [LandBlock(row: 0, column: 0), LandBlock(row: 0, column: 1)])
        let route = try world.createBusRoute(to: a, stops: [CellPosition(row: 8, column: 26)], service: .every(minutes: 10), buses: 2)
        XCTAssertEqual(world.busRoute(id: route.id)?.feederTrips, 200)
        try world.createCableway(stops: line)
        XCTAssertEqual(world.busRoute(id: route.id)?.feederTrips, 0)
        XCTAssertEqual(world.cableways[0].feederTrips, 200)
        XCTAssertEqual(trips(world, a), 600, "the same 1,000 residents, now by cableway")
    }

    /// Two stops among people and no station: the trips between them, as
    /// a city bus route's (a quarter of each stop's land, kept by the
    /// distance), and no transfer.
    func testACablewayCarriesTripsBetweenItsStops() throws {
        var world = try world()
        try world.setLand([LandCell(row: 8, column: 5, use: .residential, residents: 1_000, jobs: 0)]
            + [LandCell(row: 2, column: 30, use: .residential, residents: 2_000, jobs: 0)]
            + [LandCell(row: 2, column: 45, use: .leisure, residents: 0, jobs: 2_000)]
            + [LandCell(row: 8, column: 60, use: .office, residents: 0, jobs: 1_000)])
        let built = try world.createCableway(stops: [CablewayStop(cell: CellPosition(row: 2, column: 30)), CablewayStop(cell: CellPosition(row: 2, column: 45))])
        let cableway = try XCTUnwrap(world.cableway(id: built.id))
        XCTAssertEqual(cableway.legMetres, [960])
        XCTAssertNil(cableway.transfer)
        XCTAssertEqual(cableway.feederTrips, 0)
        XCTAssertGreaterThan(cableway.localTrips, 0)
        // Both walks 0, a minute's wait, 192 s on board, 3.2 minutes: 4.
        XCTAssertEqual(cableway.localMinutes, 4)
    }

    // MARK: - The days

    /// Day 0 is a Monday, its maintenance day: no riders, its running paid.
    /// Day 1, a Tuesday, it runs: the riders it brought the trains pay
    /// NT$180 each.
    func testItStandsStillOnMondayAndTheDaysAreBookedTogether() throws {
        var world = try world()
        let built = try world.createCableway(stops: line)
        XCTAssertFalse(world.cablewayIsOpen(built.id, onDay: 0))
        XCTAssertTrue(world.cablewayIsOpen(built.id, onDay: 1))
        try world.advance(ticks: 2 * 1_440 + 30)
        let days = try XCTUnwrap(world.cableway(id: built.id)).days
        XCTAssertEqual(days.map(\.day), [0, 1])
        XCTAssertEqual(days[0], CablewayDay(day: 0, riders: 0, fares: .zero, cost: Money(1_378 * 500), closed: true))
        XCTAssertFalse(days[1].closed)
        XCTAssertGreaterThan(days[1].riders, 0)
        XCTAssertEqual(days[1].fares, Money(days[1].riders * 18_000))
        let entry = try XCTUnwrap(world.accounts.entries.last { $0.kind == .dailyCableways })
        XCTAssertEqual(entry.breakdown, [LedgerLine(item: .cablewayFares, amount: days[1].fares), LedgerLine(item: .cablewayRunning, amount: Money(-1_378 * 500))])
        XCTAssertTrue(world.accounts.entries.allSatisfy(GameWorld.isWellFormed))
    }

    func testAThunderstormOrAHolidayMondayDecidesTooWhenItRuns() throws {
        var world = try world()
        let built = try world.createCableway(stops: line)
        world.setDisruptions(try XCTUnwrap(Disruptions(level: .standard, country: "TW", seed: 7)))
        let stormy = try XCTUnwrap((0..<720).first { world.weather(onDay: $0) == .thunderstorm && StationDemand.weekday(ofDay: $0) != 1 })
        XCTAssertFalse(world.cablewayIsOpen(built.id, onDay: stormy))
        XCTAssertTrue(world.cablewayIsOpen(built.id, onDay: stormy + 1) || world.weather(onDay: stormy + 1) == .thunderstorm
            || StationDemand.weekday(ofDay: stormy + 1) == 1 || !world.typhoons(onDay: stormy + 1).isEmpty)
        XCTAssertFalse(world.cablewayIsOpen(CablewayID(rawValue: 9), onDay: 1), "no such cableway")
    }

    // MARK: - Tourists (decision 586)

    /// ``world()`` with 1,000 residents beside B too, so tourists set out
    /// from there, and a three-star mountain at `cell`'s middle.
    private func touring(sightAt cell: CellPosition) throws -> GameWorld {
        var world = try world()
        try world.setLand([LandCell(row: 8, column: 5, use: .residential, residents: 1_000, jobs: 0)]
            + (24...28).map { LandCell(row: 8, column: $0, use: .residential, residents: 200, jobs: 0) }
            + [LandCell(row: 8, column: 59, use: .residential, residents: 1_000, jobs: 0),
               LandCell(row: 8, column: 60, use: .office, residents: 0, jobs: 1_000)])
        world.setTourism([Attraction(id: AttractionID(rawValue: 1), name: "山", englishName: "Hill",
                                     point: GameWorld.middle(of: cell), kind: .mountain, baseStars: 300)])
        return world
    }

    private func flows(_ world: GameWorld, onDay day: Int64) -> (flows: TouristFlows, arrivals: [AttractionID: Int64]) {
        let counted = world.touristFlows(onDay: day) { world.reaches(from: $0, to: $1, graph: nil) }
        return (counted.flows, counted.arrivals)
    }

    /// A sight by the far stop, 1.3 km from A and 2.2 km from B: no station
    /// serves it on foot, so its tourists ride from B to A, the station the
    /// cableway meets, and on up the rope, there and back. Not on Monday
    /// (day 0), when the rope stands still; and without the cableway none
    /// come at all.
    func testASightByAStopSendsItsTouristsUpTheRope() throws {
        var world = try touring(sightAt: CellPosition(row: 8, column: 26))
        let sight = AttractionID(rawValue: 1)
        XCTAssertNil(world.attractionStation(of: sight))
        XCTAssertTrue(flows(world, onDay: 1).flows.isEmpty, "no station serves it")
        let built = try world.createCableway(stops: line)
        XCTAssertEqual(world.attractionStation(of: sight), a)
        let tuesday = flows(world, onDay: 1)
        let tourists = try XCTUnwrap(tuesday.arrivals[sight])
        XCTAssertGreaterThan(tourists, 0)
        XCTAssertEqual(tuesday.flows.pairs[b]?[a]?.outbound, tourists)
        XCTAssertEqual(tuesday.flows.pairs[a]?[b]?.back, tourists)
        XCTAssertEqual(tuesday.flows.feederRides, [.cableway(built.id): 2 * tourists], "up and down")
        let monday = flows(world, onDay: 0)
        XCTAssertNil(monday.arrivals[sight])
        XCTAssertTrue(monday.flows.feederRides.isEmpty)
        XCTAssertEqual(world.attractionStation(of: sight), a, "served on a Monday too")
    }

    /// A sight by the stop that meets A is A's on foot: the railway keeps
    /// it, and the rope carries none of its tourists.
    func testASightAStationReachesStaysTheStations() throws {
        var world = try touring(sightAt: CellPosition(row: 8, column: 6))
        let before = flows(world, onDay: 1)
        try world.createCableway(stops: line)
        let after = flows(world, onDay: 1)
        XCTAssertEqual(world.attractionStation(of: AttractionID(rawValue: 1)), a)
        XCTAssertTrue(after.flows.feederRides.isEmpty)
        XCTAssertEqual(after.arrivals, before.arrivals)
        XCTAssertEqual(after.flows.pairs[b]?[a]?.outbound, before.flows.pairs[b]?[a]?.outbound)
    }

    /// The tourists' rides join the riders of the day they rode: Tuesday's
    /// riders are those the trains brought and the tourists, up and down.
    func testTheTouristsRidesAreBookedWithTheDay() throws {
        var touring = try touring(sightAt: CellPosition(row: 8, column: 26))
        let built = try touring.createCableway(stops: line)
        let rides = try XCTUnwrap(flows(touring, onDay: 1).flows.feederRides[.cableway(built.id)])
        var plain = touring
        plain.setTourism(nil)
        try touring.advance(ticks: 2 * 1_440 + 30)
        try plain.advance(ticks: 2 * 1_440 + 30)
        let toured = try XCTUnwrap(touring.cableway(id: built.id)).days
        let days = try XCTUnwrap(plain.cableway(id: built.id)).days
        XCTAssertEqual(toured[0].riders, 0, "Monday")
        XCTAssertGreaterThanOrEqual(toured[1].riders, days[1].riders + rides)
        XCTAssertEqual(toured[1].fares, Money(toured[1].riders * 18_000))
    }

    // MARK: - Refused

    func testABadCablewayIsRefusedAndChangesNothing() throws {
        var world = try world()
        let before = world
        func refused(_ stops: [CablewayStop], _ legs: [Int64]? = nil, why: String) {
            let error = GameError.invalidCableway
            XCTAssertThrowsError(try world.createCableway(stops: stops, legMetres: legs), why) { XCTAssertEqual($0 as? GameError, error, why) }
            XCTAssertEqual(world, before, why)
        }
        let here = CablewayStop(cell: CellPosition(row: 8, column: 6)), there = CablewayStop(cell: CellPosition(row: 8, column: 26))
        refused([here], why: "one stop")
        refused(Array(repeating: [here, there], count: 5).flatMap { $0 }, why: "nine stops")
        refused([here, CablewayStop(cell: CellPosition(row: 4, column: 16), boards: false)], why: "an angle station at an end")
        refused([here, here, there], why: "two stops in a row on one cell")
        refused([here, CablewayStop(cell: CellPosition(row: 16, column: 0))], why: "a stop off the world")
        refused([here, there], [1, 2], why: "a span too many")
        refused([here, there], [0], why: "a span of nothing")
        refused([here, there], [5_001], why: "a span too long")
        // Eight stops and 35 km of rope: NT$52.5 million and more.
        let far = (0..<8).map { CablewayStop(cell: CellPosition(row: $0 % 2, column: $0)) }
        XCTAssertThrowsError(try world.createCableway(stops: far, legMetres: Array(repeating: 5_000, count: 7))) {
            guard case .insufficientFunds = $0 as? GameError else { return XCTFail("\($0)") }
        }
        XCTAssertEqual(world, before)
        XCTAssertThrowsError(try world.removeCableway(CablewayID(rawValue: 1))) { XCTAssertEqual($0 as? GameError, .unknownCableway(CablewayID(rawValue: 1))) }
    }

    /// The station it meets closes: it meets none, and brings no one.
    func testRemovingTheStationItMeetsLeavesItMeetingNone() throws {
        var world = try world()
        let built = try world.createCableway(stops: line)
        try world.removeStation(a)
        let cableway = try XCTUnwrap(world.cableway(id: built.id))
        XCTAssertNil(cableway.transfer)
        XCTAssertEqual(cableway.feederTrips, 0)
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world)), world, "it still loads")
    }

    /// REVIEW-L10, L10-2 (decision 587, continued, as a city bus
    /// route's): a depot is no transfer. C, a station of no line on the
    /// first stop's cell, is nearer it than A is: the cableway meets C;
    /// once C is a depot it meets A, its riders with it, and C again when
    /// it is a station again.
    func testACablewayMeetsNoDepot() throws {
        var world = try world()
        let c = try world.buildStation(named: "C", at: GameWorld.middle(of: line[0].cell)).id
        let built = try world.createCableway(stops: line)
        XCTAssertEqual(world.cableway(id: built.id)?.transfer, BusTransfer(station: c, stop: 0))
        try world.setStationDepot(c, to: true)
        let met = try XCTUnwrap(world.cableway(id: built.id))
        XCTAssertEqual(met.transfer, BusTransfer(station: a, stop: 0))
        XCTAssertEqual(met.feederTrips, 200)
        var alone = try self.world()
        _ = try alone.buildStation(named: "C", at: try XCTUnwrap(world.station(id: c)).location)
        try alone.setStationDepot(c, to: true)
        XCTAssertEqual(trips(world, a), try XCTUnwrap(trips(alone, a)) + 200, "the riders go to A")
        try world.setStationDepot(c, to: false)
        XCTAssertEqual(world.cableway(id: built.id)?.transfer, BusTransfer(station: c, stop: 0))
    }

    // MARK: - The station a real one meets (decision 586)

    /// A stop seven cells from A, 400 to 500 m off: on its own it meets
    /// nothing; given A's place it meets A, keeps that through a save, and
    /// meets it again once A is rebuilt there.
    func testAGivenStationIsMetUpToFiveHundredMetres() throws {
        var world = try world()
        let near = CablewayStop(cell: CellPosition(row: 8, column: 12)), far = CablewayStop(cell: CellPosition(row: 8, column: 26))
        let place = try XCTUnwrap(world.station(id: a)).location
        let squared = GameWorld.squaredDistance(GameWorld.middle(of: near.cell), place)
        XCTAssertGreaterThan(squared, BusRoute.stopReach * BusRoute.stopReach, "beyond the 400 m a cableway finds a station in")
        XCTAssertLessThanOrEqual(squared, Cableway.namedTransferReach * Cableway.namedTransferReach, "within 500 m")
        var unnamed = world
        let plain = try unnamed.createCableway(stops: [near, far])
        XCTAssertNil(unnamed.cableway(id: plain.id)?.transfer)
        XCTAssertNil(unnamed.cableway(id: plain.id)?.meetsNear)
        let built = try world.createCableway(stops: [near, far], meetsNear: place)
        let cableway = try XCTUnwrap(world.cableway(id: built.id))
        XCTAssertEqual(cableway.meetsNear, place)
        XCTAssertEqual(cableway.transfer, BusTransfer(station: a, stop: 0))
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world)), world, "it loads with its station")
        try world.removeStation(a)
        XCTAssertNil(world.cableway(id: built.id)?.transfer)
        XCTAssertEqual(world.cableway(id: built.id)?.meetsNear, place, "it still knows where its station stood")
    }

    /// REVIEW-L10, L10-2: a cableway given a station's place (decision
    /// 586) meets no depot there either: C stands on the place, so the
    /// cableway meets C; once C is a depot it meets A, the next nearest.
    func testAGivenStationIsNeverADepot() throws {
        var world = try world()
        let near = CablewayStop(cell: CellPosition(row: 8, column: 12)), far = CablewayStop(cell: CellPosition(row: 8, column: 26))
        let place = GameWorld.middle(of: CellPosition(row: 8, column: 9))
        let c = try world.buildStation(named: "C", at: place).id
        let built = try world.createCableway(stops: [near, far], meetsNear: place)
        XCTAssertEqual(world.cableway(id: built.id)?.transfer, BusTransfer(station: c, stop: 0))
        try world.setStationDepot(c, to: true)
        XCTAssertEqual(world.cableway(id: built.id)?.transfer, BusTransfer(station: a, stop: 0))
    }

    /// A place more than 500 m from every boarding stop is refused, and
    /// the world is unchanged; the angle station does not count.
    func testAGivenStationTooFarIsRefused() throws {
        var world = try world()
        let before = world
        let place = try XCTUnwrap(world.station(id: a)).location
        for (stops, why) in [([CablewayStop(cell: CellPosition(row: 8, column: 14)), CablewayStop(cell: CellPosition(row: 8, column: 26))], "nine cells off"),
                             ([CablewayStop(cell: CellPosition(row: 8, column: 26)), CablewayStop(cell: CellPosition(row: 8, column: 12), boards: false),
                               CablewayStop(cell: CellPosition(row: 8, column: 40))], "only an angle station near")] {
            XCTAssertThrowsError(try world.createCableway(stops: stops, meetsNear: place), why) { XCTAssertEqual($0 as? GameError, .invalidCableway, why) }
            XCTAssertEqual(world, before, why)
        }
    }

    // MARK: - The save

    /// Version 83 (decision 574): the cableway and its two days, saved byte
    /// for byte; it is the world this build makes.
    func testVersionEightyThreeKeepsTheCableway() throws {
        var made = try world()
        try made.createCableway(stops: line)
        try made.advance(ticks: 2 * 1_440 + 30)
        let url = SavedGameTests.fixtures.appendingPathComponent("v83-cableway.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["CABLEWAY_SAVE_NEW"] != nil {
            try encoder.encode(SavedGame(world: made)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 83)
        let world = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(world, made)
        XCTAssertEqual(world.cableways.count, 1)
        XCTAssertEqual(world.cableways[0].stops, line)
        XCTAssertEqual(world.cableways[0].days.map(\.closed), [true, false])
        XCTAssertEqual(world.nextCablewayID, 2)
        XCTAssertEqual(try encoder.encode(SavedGame(world: world)), Data(String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #""saveVersion" : 83,"#, with: #""saveVersion" : \#(SavedGame.currentVersion),"#).utf8))
    }

    func testDamagedCablewaysAreRefused() throws {
        var world = try world()
        try world.createCableway(stops: line)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(SavedGame(world: world))) as? [String: Any])
        let saved = try XCTUnwrap(object["world"] as? [String: Any])
        let cableway = try XCTUnwrap((saved["cableways"] as? [[String: Any]])?.first)
        func load(_ change: (inout [String: Any], inout [String: Any]) -> Void) throws {
            var plain = object, world = saved, rope = cableway
            change(&world, &rope)
            world["cableways"] = [rope]
            plain["world"] = world
            _ = try JSONDecoder().decode(SavedGame.self, from: JSONSerialization.data(withJSONObject: plain))
        }
        XCTAssertNoThrow(try load { _, _ in })
        XCTAssertThrowsError(try load { world, _ in world["nextCablewayID"] = 1 }, "a number not handed out")
        XCTAssertThrowsError(try load { _, rope in rope["id"] = 0 }, "numbered 0")
        XCTAssertThrowsError(try load { _, rope in rope["legMetres"] = [1] }, "a span short")
        XCTAssertThrowsError(try load { _, rope in rope["legMetres"] = [0, 689] }, "a span of nothing")
        XCTAssertThrowsError(try load { _, rope in rope["stops"] = [["row": 16, "column": 0], ["row": 8, "column": 26], ["row": 8, "column": 27]] }, "a stop off the world")
        XCTAssertThrowsError(try load { _, rope in rope["stops"] = [["row": 8, "column": 6, "angle": true], ["row": 4, "column": 16], ["row": 8, "column": 26]] },
                             "an angle station at an end")
        XCTAssertThrowsError(try load { _, rope in rope["transfer"] = ["station": 9, "stop": 0] }, "a station the world has not")
        XCTAssertThrowsError(try load { _, rope in rope["transfer"] = ["station": 1, "stop": 1] }, "a transfer at an angle station")
        XCTAssertThrowsError(try load { _, rope in rope["stops"] = Array(repeating: ["row": 0, "column": 0], count: 9) }, "too many stops")
    }
}
