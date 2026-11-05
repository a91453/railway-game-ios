import Foundation
@testable import GameCore
import XCTest

/// The company's ferries (decision 585): the crossings, boats, headway and
/// capacity, the piers beside the water, the land a pier brings in and the
/// trips between its piers, the days a typhoon keeps the boats in, the
/// fares and running costs, the commands and the save. Every expectation
/// is worked out by hand from the rules; a cell is 4,096 units (64 m).
final class FerryTests: XCTestCase {
    private static let track = TestLine(tiles: 256, row: 33)
    private let cell = Land.cellLength
    private let a = StationID(rawValue: 1)
    private let b = StationID(rawValue: 2)
    /// A pier by A and one out among the five cells of 200 residents, on
    /// the shore of row 6: one crossing of 1,280 m (20 cells).
    private let piers = [CellPosition(row: 6, column: 6), CellPosition(row: 6, column: 26)]

    /// CablewayTests' world (BusRouteTests' without roads) with a channel
    /// of water across rows 4 and 5: a managed world of 64 × 16 cells with
    /// land demand, A beside tile 21 (cell (8, 5)) and B beside tile 241,
    /// a train between them; A's cell has 1,000 residents, B's 1,000 office
    /// jobs, cells (8, 24) to (8, 28), out of A's 800 m, 200 residents
    /// each. A minute a tick.
    private func world(balance: Money = 1_000_000_000) throws -> GameWorld {
        var world = GameWorld(bounds: try WorldBounds(width: 64 * cell, height: 16 * cell), economy: GameEconomy(balance: balance, costs: testCosts))
        try world.setWater((4...5).flatMap { row in (0..<64).map { CellPosition(row: row, column: $0) } })
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

    // MARK: - The boats

    /// Tamsui–Bali: about 1,400 m. At 12 km/h, 7 minutes across; there and
    /// back 14 minutes under way and 2 at each end of each crossing, 18.
    /// One boat keeps a boat every 18 minutes however often it is asked
    /// to; two keep 15. A headway runs 07:00 to 19:00 on a weekday (12
    /// hours, 48 boats every 15 minutes) and to 20:00 on a weekend (52).
    func testTheCrossingAndTheBoatsAreTamsuiBalis() {
        var tamsui = FerryRoute(id: FerryRouteID(rawValue: 1), piers: piers, legMetres: [1_400], service: .every(minutes: 15), boats: 1)
        XCTAssertEqual(tamsui.rideMinutes(from: 0, to: 1), 7)
        XCTAssertEqual(tamsui.rideMinutes(from: 1, to: 0), 7, "the same both ways")
        XCTAssertEqual(tamsui.roundTripMinutes, 18)
        XCTAssertEqual(tamsui.headway, 18)
        XCTAssertEqual(tamsui.dailyDepartures(onDay: 1), 40, "day 1 is a Tuesday: 720 minutes over 18")
        tamsui.boats = 2
        XCTAssertEqual(tamsui.headway, 15)
        XCTAssertEqual(tamsui.dailyDepartures(onDay: 1), 48)
        XCTAssertEqual(tamsui.dailyDepartures(onDay: 5), 52, "day 5 is a Saturday: 780 minutes")
        XCTAssertEqual(tamsui.dailyCapacity(onDay: 1), 48 * 2 * 99)
        // 48 boats there and back, 2.8 km each, at NT$300 a kilometre.
        XCTAssertEqual(tamsui.dailyCost(onDay: 1), Money(48 * 2_800 * 30))
        tamsui.boats = 0
        XCTAssertNil(tamsui.headway)
        XCTAssertEqual(tamsui.dailyDepartures(onDay: 1), 0)
        XCTAssertEqual(tamsui.dailyCost(onDay: 1), .zero)
        // A real timetable sails its runs, whatever the hours.
        tamsui.boats = 1
        tamsui.service = .runs([420, 440, 460])
        XCTAssertEqual(tamsui.dailyDepartures(onDay: 1), 3)
        // A pier between: 2 more minutes on the way through.
        let three = FerryRoute(id: FerryRouteID(rawValue: 2), piers: piers + [CellPosition(row: 6, column: 40)], legMetres: [1_400, 600],
                               service: .every(minutes: 10), boats: 1)
        XCTAssertEqual(three.rideMinutes(from: 0, to: 2), 10 + 2)
        XCTAssertEqual(three.roundTripMinutes, 20 + 8)
        XCTAssertEqual(FerryRoute.price(piers: 3, boats: 2), Money(3 * 30_000_000 + 2 * 100_000_000))
        XCTAssertTrue(three.isValid)
    }

    // MARK: - The piers

    func testAPierStandsOnTheShore() throws {
        let world = try world()
        XCTAssertTrue(world.isPierCell(row: 6, column: 6), "water above")
        XCTAssertTrue(world.isPierCell(row: 3, column: 0), "water below, at the world's edge")
        XCTAssertFalse(world.isPierCell(row: 5, column: 6), "on the water")
        XCTAssertFalse(world.isPierCell(row: 7, column: 6), "water only two cells off")
        XCTAssertFalse(world.isPierCell(row: 16, column: 6), "off the world")
        XCTAssertFalse(GameWorld(bounds: world.bounds, economy: GameEconomy(balance: 0, costs: testCosts)).isPierCell(row: 6, column: 6), "a world without water has no shore")
    }

    // MARK: - The land it draws

    /// The far pier at (6, 26) reaches the five cells: 1,000 residents,
    /// riding half as much as A's own (500 people), 200 trips, to A, which
    /// the first pier meets. Their minutes: the walk 3, 2, 2, 2, 3; half
    /// the 15-minute headway two boats keep, 8; 6 across (1,280 m); and
    /// the walk from the first pier to A, 2: 18.4 on average, 18.
    func testAPierBringsInTheLandNoStationReaches() throws {
        var world = try world()
        XCTAssertEqual(trips(world, a), 400)
        let balance = world.economy.balance
        let built = try world.createFerryRoute(piers: piers, service: .every(minutes: 15), boats: 2)
        XCTAssertEqual(built.id, FerryRouteID(rawValue: 1))
        XCTAssertEqual(built.legMetres, [1_280])
        let route = try XCTUnwrap(world.ferryRoute(id: built.id))
        XCTAssertEqual(route.headway, 15)
        XCTAssertEqual(route.transfer, BusTransfer(station: a, stop: 0))
        XCTAssertEqual(route.feederTrips, 200)
        XCTAssertEqual(route.feederMinutes, 18)
        XCTAssertEqual(route.localTrips, 0, "only the far pier has people of its own")
        XCTAssertEqual(trips(world, a), 600)
        XCTAssertEqual(trips(world, b), 400)
        XCTAssertEqual(world.economy.balance, Money(balance.amount - 2 * 30_000_000 - 2 * 100_000_000))
        // No boat: no one rides.
        try world.setFerryBoats(built.id, to: 0)
        XCTAssertEqual(world.ferryRoute(id: built.id)?.feederTrips, 0)
        XCTAssertEqual(trips(world, a), 400)
        XCTAssertEqual(world.economy.balance, Money(balance.amount - 2 * 30_000_000 - 2 * 100_000_000), "nothing sold back")
        try world.setFerryBoats(built.id, to: 1)
        XCTAssertEqual(world.economy.balance, Money(balance.amount - 2 * 30_000_000 - 3 * 100_000_000))
        XCTAssertEqual(world.ferryRoute(id: built.id)?.feederTrips, 200)
        try world.setFerryRuns(built.id, to: .every(minutes: 30))
        XCTAssertEqual(world.ferryRoute(id: built.id)?.headway, 30)
        try world.removeFerryRoute(built.id)
        XCTAssertNil(world.ferryRoute(id: built.id))
        XCTAssertEqual(trips(world, a), 400)
    }

    /// REVIEW-L10, L10-2 (decision 587, continued, as a city bus
    /// route's): a depot is no transfer. C, a station of no line on the
    /// first pier, is nearer it than A is: the route meets C; once C is a
    /// depot it meets A, its riders with it, and C again when it is a
    /// station again.
    func testAFerryMeetsNoDepot() throws {
        var world = try world()
        let c = try world.buildStation(named: "C", at: GameWorld.middle(of: piers[0])).id
        let built = try world.createFerryRoute(piers: piers, service: .every(minutes: 15), boats: 2)
        XCTAssertEqual(world.ferryRoute(id: built.id)?.transfer, BusTransfer(station: c, stop: 0))
        try world.setStationDepot(c, to: true)
        let met = try XCTUnwrap(world.ferryRoute(id: built.id))
        XCTAssertEqual(met.transfer, BusTransfer(station: a, stop: 0))
        XCTAssertEqual(met.feederTrips, 200)
        var alone = try self.world()
        _ = try alone.buildStation(named: "C", at: try XCTUnwrap(world.station(id: c)).location)
        try alone.setStationDepot(c, to: true)
        XCTAssertEqual(trips(world, a), try XCTUnwrap(trips(alone, a)) + 200, "the riders go to A")
        try world.setStationDepot(c, to: false)
        XCTAssertEqual(world.ferryRoute(id: built.id)?.transfer, BusTransfer(station: c, stop: 0))
    }

    /// A cableway takes its land first, and a ferry's land is no bus's.
    func testACablewayThenAFerryThenABusShareTheLand() throws {
        var world = try world()
        world.enableRoads()
        try world.setRoads((5...30).map { CellPosition(row: 8, column: $0) }, in: [LandBlock(row: 0, column: 0), LandBlock(row: 0, column: 1)])
        let bus = try world.createBusRoute(to: a, stops: [CellPosition(row: 8, column: 26)], service: .every(minutes: 10), buses: 2)
        XCTAssertEqual(world.busRoute(id: bus.id)?.feederTrips, 200)
        let ferry = try world.createFerryRoute(piers: piers, service: .every(minutes: 15), boats: 2)
        XCTAssertEqual(world.busRoute(id: bus.id)?.feederTrips, 0)
        XCTAssertEqual(world.ferryRoute(id: ferry.id)?.feederTrips, 200)
        try world.createCableway(stops: [CablewayStop(cell: CellPosition(row: 8, column: 6)), CablewayStop(cell: CellPosition(row: 8, column: 26))])
        XCTAssertEqual(world.ferryRoute(id: ferry.id)?.feederTrips, 0)
        XCTAssertEqual(world.cableways[0].feederTrips, 200)
        XCTAssertEqual(trips(world, a), 600, "the same 1,000 residents, now by cableway")
    }

    /// Two piers among people and no station: the trips between them, as
    /// a cableway's, and no transfer.
    func testAFerryCarriesTripsBetweenItsPiers() throws {
        var world = try world()
        try world.setLand([LandCell(row: 8, column: 5, use: .residential, residents: 1_000, jobs: 0)]
            + [LandCell(row: 3, column: 30, use: .residential, residents: 2_000, jobs: 0)]
            + [LandCell(row: 6, column: 45, use: .leisure, residents: 0, jobs: 2_000)]
            + [LandCell(row: 8, column: 60, use: .office, residents: 0, jobs: 1_000)])
        let built = try world.createFerryRoute(piers: [CellPosition(row: 3, column: 30), CellPosition(row: 6, column: 45)],
                                               service: .every(minutes: 20), boats: 1)
        let route = try XCTUnwrap(world.ferryRoute(id: built.id))
        // 15 across and 3 down: 979 m.
        XCTAssertEqual(route.legMetres, [979])
        XCTAssertNil(route.transfer)
        XCTAssertEqual(route.feederTrips, 0)
        XCTAssertGreaterThan(route.localTrips, 0)
        // Both walks 0; the boat's 14 minutes there and back keep the 20
        // asked for, half of it 10; 979 m across, 4.9 minutes, 5: 15.
        XCTAssertEqual(route.headway, 20)
        XCTAssertEqual(route.localMinutes, 15)
    }

    // MARK: - The days

    /// Day 0 and day 1 the boats sail: the riders they brought the trains
    /// pay NT$40 each, and the boats' kilometres are paid.
    func testTheDaysAreBookedTogether() throws {
        var world = try world()
        let built = try world.createFerryRoute(piers: piers, service: .every(minutes: 15), boats: 2)
        XCTAssertTrue(world.ferryRouteIsOpen(built.id, onDay: 0))
        try world.advance(ticks: 2 * 1_440 + 30)
        let days = try XCTUnwrap(world.ferryRoute(id: built.id)).days
        XCTAssertEqual(days.map(\.day), [0, 1])
        // 48 boats a weekday each way, 2,560 m there and back, NT$300 a km.
        let cost = Money(48 * 2_560 * 30)
        XCTAssertFalse(days[1].closed)
        XCTAssertGreaterThan(days[1].riders, 0)
        XCTAssertEqual(days[1].fares, Money(days[1].riders * 4_000))
        XCTAssertEqual(days[1].cost, cost)
        let entry = try XCTUnwrap(world.accounts.entries.last { $0.kind == .dailyFerries })
        XCTAssertEqual(entry.breakdown, [LedgerLine(item: .ferryFares, amount: days[1].fares), LedgerLine(item: .ferryRunning, amount: .zero - cost)])
        XCTAssertTrue(world.accounts.entries.allSatisfy(GameWorld.isWellFormed))
    }

    /// A typhoon over a pier keeps the boats in; a thunderstorm does not.
    func testATyphoonKeepsTheBoatsIn() throws {
        var world = try world()
        let built = try world.createFerryRoute(piers: piers, service: .every(minutes: 15), boats: 2)
        world.setDisruptions(try XCTUnwrap(Disruptions(level: .standard, country: "TW", seed: 7)))
        let pier = GameWorld.middle(of: piers[0])
        let stormy = try XCTUnwrap((0..<720).first { day in world.typhoons(onDay: day).contains { $0.isActive(onDay: day) && $0.covers(pier) } })
        XCTAssertFalse(world.ferryRouteIsOpen(built.id, onDay: stormy))
        if let thunder = (0..<720).first(where: { day in world.weather(onDay: day) == .thunderstorm && world.typhoons(onDay: day).isEmpty }) {
            XCTAssertTrue(world.ferryRouteIsOpen(built.id, onDay: thunder))
        }
        XCTAssertFalse(world.ferryRouteIsOpen(FerryRouteID(rawValue: 9), onDay: 1), "no such route")
    }

    // MARK: - Refused

    func testABadFerryRouteIsRefusedAndChangesNothing() throws {
        var world = try world()
        let before = world
        func refused(_ piers: [CellPosition], _ legs: [Int64]? = nil, service: BusService = .every(minutes: 15), boats: Int = 1,
                     _ error: GameError = .invalidFerryRoute, why: String) {
            XCTAssertThrowsError(try world.createFerryRoute(piers: piers, legMetres: legs, service: service, boats: boats), why) {
                XCTAssertEqual($0 as? GameError, error, why)
            }
            XCTAssertEqual(world, before, why)
        }
        let here = piers[0], there = piers[1]
        refused([here], why: "one pier")
        refused(Array(repeating: [here, there], count: 5).flatMap { $0 }, why: "nine piers")
        refused([here, here, there], why: "two piers in a row on one cell")
        refused([here, CellPosition(row: 16, column: 0)], why: "a pier off the world")
        refused([here, there], [1, 2], why: "a crossing too many")
        refused([here, there], [0], why: "a crossing of nothing")
        refused([here, there], [30_001], why: "a crossing too long")
        refused([here, there], service: .every(minutes: 0), why: "no headway")
        refused([here, there], boats: 21, why: "too many boats")
        refused([here, CellPosition(row: 5, column: 26)], nil, .pierNotBesideWater(row: 5, column: 26), why: "a pier on the water")
        refused([CellPosition(row: 8, column: 6), there], nil, .pierNotBesideWater(row: 8, column: 6), why: "a pier inland")
        XCTAssertThrowsError(try world.createFerryRoute(piers: piers, service: .every(minutes: 15), boats: 20)) {
            guard case .insufficientFunds = $0 as? GameError else { return XCTFail("\($0)") }
        }
        XCTAssertEqual(world, before)
        let unknown = FerryRouteID(rawValue: 1)
        XCTAssertThrowsError(try world.removeFerryRoute(unknown)) { XCTAssertEqual($0 as? GameError, .unknownFerryRoute(unknown)) }
        XCTAssertThrowsError(try world.setFerryBoats(unknown, to: 1)) { XCTAssertEqual($0 as? GameError, .unknownFerryRoute(unknown)) }
        XCTAssertThrowsError(try world.setFerryRuns(unknown, to: .every(minutes: 5))) { XCTAssertEqual($0 as? GameError, .unknownFerryRoute(unknown)) }
        let built = try world.createFerryRoute(piers: piers, service: .every(minutes: 15), boats: 1)
        let opened = world
        XCTAssertThrowsError(try world.setFerryBoats(built.id, to: 21)) { XCTAssertEqual($0 as? GameError, .invalidFerryRoute) }
        XCTAssertThrowsError(try world.setFerryRuns(built.id, to: .runs([]))) { XCTAssertEqual($0 as? GameError, .invalidFerryRoute) }
        XCTAssertEqual(world, opened)
    }

    /// The station it meets closes: it meets none, and brings no one.
    func testRemovingTheStationItMeetsLeavesItMeetingNone() throws {
        var world = try world()
        let built = try world.createFerryRoute(piers: piers, service: .every(minutes: 15), boats: 2)
        try world.removeStation(a)
        let route = try XCTUnwrap(world.ferryRoute(id: built.id))
        XCTAssertNil(route.transfer)
        XCTAssertEqual(route.feederTrips, 0)
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world)), world, "it still loads")
    }

    // MARK: - The save

    /// Version 85 (decision 585): the ferry route and its two days, saved
    /// byte for byte; it is the world this build makes.
    func testVersionEightyFiveKeepsTheFerry() throws {
        var made = try world()
        try made.createFerryRoute(piers: piers, service: .every(minutes: 15), boats: 2)
        try made.advance(ticks: 2 * 1_440 + 30)
        let url = SavedGameTests.fixtures.appendingPathComponent("v85-ferry.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["FERRY_SAVE_NEW"] != nil {
            try encoder.encode(SavedGame(world: made)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 85)
        let world = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(world, made)
        XCTAssertEqual(world.ferryRoutes.count, 1)
        XCTAssertEqual(world.ferryRoutes[0].piers, piers)
        XCTAssertEqual(world.ferryRoutes[0].boats, 2)
        XCTAssertEqual(world.ferryRoutes[0].days.map(\.day), [0, 1])
        XCTAssertEqual(world.nextFerryRouteID, 2)
        XCTAssertEqual(try encoder.encode(SavedGame(world: world)), Data(String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #""saveVersion" : 85,"#, with: #""saveVersion" : \#(SavedGame.currentVersion),"#).utf8))
    }

    func testDamagedFerryRoutesAreRefused() throws {
        var world = try world()
        try world.createFerryRoute(piers: piers, service: .every(minutes: 15), boats: 2)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(SavedGame(world: world))) as? [String: Any])
        let saved = try XCTUnwrap(object["world"] as? [String: Any])
        let route = try XCTUnwrap((saved["ferryRoutes"] as? [[String: Any]])?.first)
        func load(_ change: (inout [String: Any], inout [String: Any]) -> Void) throws {
            var plain = object, world = saved, ferry = route
            change(&world, &ferry)
            world["ferryRoutes"] = [ferry]
            plain["world"] = world
            _ = try JSONDecoder().decode(SavedGame.self, from: JSONSerialization.data(withJSONObject: plain))
        }
        XCTAssertNoThrow(try load { _, _ in })
        XCTAssertThrowsError(try load { world, _ in world["nextFerryRouteID"] = 1 }, "a number not handed out")
        XCTAssertThrowsError(try load { _, ferry in ferry["id"] = 0 }, "numbered 0")
        XCTAssertThrowsError(try load { _, ferry in ferry["legMetres"] = [1, 2] }, "a crossing too many")
        XCTAssertThrowsError(try load { _, ferry in ferry["legMetres"] = [0] }, "a crossing of nothing")
        XCTAssertThrowsError(try load { _, ferry in ferry["piers"] = [["row": 16, "column": 0], ["row": 6, "column": 26]] }, "a pier off the world")
        XCTAssertThrowsError(try load { _, ferry in ferry["boats"] = 21 }, "too many boats")
        XCTAssertThrowsError(try load { _, ferry in ferry["service"] = ["every": 0] }, "no headway")
        XCTAssertThrowsError(try load { _, ferry in ferry["transfer"] = ["station": 9, "stop": 0] }, "a station the world has not")
        XCTAssertThrowsError(try load { _, ferry in ferry["transfer"] = ["station": 1, "stop": 2] }, "a transfer at no pier")
        XCTAssertThrowsError(try load { _, ferry in ferry["piers"] = Array(repeating: ["row": 6, "column": 0], count: 9) }, "too many piers")
    }
}
