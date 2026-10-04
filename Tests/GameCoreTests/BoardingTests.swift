import Foundation
@testable import GameCore
import XCTest

/// G1b (ARCHITECTURE decision 35): trains let passengers off at their
/// destination and take on those waiting for their line and direction, the
/// farthest first, up to their capacity, once their doors have opened at
/// each stop (Stage W2b, decision 39); a full train counts those it leaves
/// behind as refused when it leaves. Every expectation here is worked out
/// by hand from the rules.
final class BoardingTests: XCTestCase {
    // The line of `LineDispatchTests`, dead ends at both ends, on the track
    // network (Stage F3b): a node at each tile centre, edges of 1024 between
    // them, and a platform either side of b, d and f (see `TestLine`):
    //
    //   Alpha(1,0)  Beta(3,0)  Gamma(5,0)
    //       |           |          |
    //   a - b - c - d - e - f - g
    //
    // Line 1 calls at Alpha, Beta and Gamma with the standard performance:
    // each leg is two links in 16 s (Stage W2c: the least second its curve
    // is built for, √(2 × 2048 × 0.06) = 15.68 s). Its round trip for a
    // train sent out at 0 is Alpha 0–0:42, Beta 0:58–1:58, Gamma 2:14–4:14
    // (turning round), Beta 4:30–5:30 and Alpha 5:46 (turning round; the
    // service ends once the train has dwelt there). Passengers get off and
    // on 8 s after the train arrives, as its doors open: at 0:08, 1:06,
    // 2:22, 4:38 and 5:54 on time.
    private let line = TestLine(tiles: 7)
    private let alpha = StationID(rawValue: 1)
    private let beta = StationID(rawValue: 2)
    private let gamma = StationID(rawValue: 3)
    private let main = LineID(rawValue: 1)
    private let other = LineID(rawValue: 2)
    private let one = TrainID(rawValue: 1)

    private func makeWorld(cars: Int = 1) throws -> GameWorld {
        var world = try GameWorld(
            bounds: WorldBounds(width: 8_192, height: 4_096), economy: GameEconomy(balance: 1_000_000, costs: testCosts),
            clock: GameClock(speed: .normal)
        )
        try line.build(in: &world)
        try line.buildStation(named: "Alpha", beside: 1, at: 0, in: &world)
        try line.buildStation(named: "Beta", beside: 3, at: 0, in: &world)
        try line.buildStation(named: "Gamma", beside: 5, at: 0, in: &world)
        try world.createLine(named: "Main", stops: [alpha, beta, gamma])
        try world.createLine(named: "Other", stops: [alpha, beta, gamma])
        try world.setLineServiceWindow(main, to: .allDay)
        try world.setLineTrainsInService(main, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        let train = try world.purchaseTrain(named: "T1")
        try world.setTrainCars(train.id, to: cars)
        try world.placeTrain(train.id, at: line.at(cars, facingEast: true))
        try world.setTrainMovementRate(train.id, to: 1024)
        try world.assignTrain(train.id, to: main)
        // A record for each station, so passengers can be put in its queue.
        for station in [alpha, beta, gamma] {
            try world.setStationDemand(station, to: StationDemand(kind: .office, dailyTrips: 0))
        }
        return world
    }

    /// Puts `count` passengers for `destination` in `station`'s queue, as
    /// released at minute `since` along `line` in `direction`.
    private func wait(
        _ world: inout GameWorld, _ count: Int64, at station: StationID, for destination: StationID,
        _ direction: LineDirection, line: LineID? = nil, since: Int64 = 0
    ) {
        let index = world.passengers.firstIndex { $0.station == station }!
        world.passengers[index].release(
            count, to: destination, along: PassengerTrip(line: line ?? main, direction: direction), at: GameTime(minutes: since)
        )
    }

    private func riding(_ origin: StationID, _ destination: StationID, _ count: Int64) -> RidingGroup {
        RidingGroup(origin: origin, destination: destination, count: count)
    }

    private func assertConserved(_ world: GameWorld, file: StaticString = #filePath, line: UInt = #line) {
        for record in world.passengers {
            let ledger = world.passengerLedger(of: record.station)
            XCTAssertEqual(
                ledger.released, ledger.waiting + ledger.riding + ledger.arrived + ledger.overflowed + ledger.abandoned,
                "station \(record.station.rawValue)", file: file, line: line
            )
        }
    }

    // MARK: - Capacity

    /// 320 rated and 352 at most a car: the reference's 1,920 for six cars,
    /// and that × 1.1.
    func testCapacityIsCarsTimesTheReferencesPerCarLoad() throws {
        XCTAssertEqual(Train.ratedCapacityPerCar * 6, 1_920)
        XCTAssertEqual(Train.capacityPerCar * 10, Train.ratedCapacityPerCar * 11)
        let world = try makeWorld(cars: 3)
        let train = try XCTUnwrap(world.train(id: one))
        XCTAssertEqual(train.ratedCapacity, 960)
        XCTAssertEqual(train.capacity, 1_056)
    }

    // MARK: - On and off

    /// At Alpha the train takes both groups; each gets off once the train's
    /// doors open at its destination.
    func testPassengersBoardAsTheTrainLeavesAndGetOffAtTheirDestination() throws {
        var world = try makeWorld()
        wait(&world, 5, at: alpha, for: beta, .outbound)
        wait(&world, 7, at: alpha, for: gamma, .outbound)

        try world.advance(ticks: 1)
        XCTAssertEqual(world.riders(of: one), [riding(alpha, beta, 5), riding(alpha, gamma, 7)])
        XCTAssertEqual(world.riderCount(of: one), 12)
        XCTAssertEqual(world.waitingPassengers(at: alpha), [])
        XCTAssertEqual(world.passengerLedger(of: alpha), PassengerLedger(released: 12, waiting: 0, riding: 12, overflowed: 0, abandoned: 0))

        // Off at Beta at 1:06, as its doors open; the rest at Gamma at 2:22.
        try world.advance(ticks: 1)
        XCTAssertEqual(world.riders(of: one), [riding(alpha, gamma, 7)])
        XCTAssertEqual(world.passengerLedger(of: alpha).arrived, 5)

        try world.advance(ticks: 1)
        XCTAssertEqual(world.riders, [])
        XCTAssertEqual(world.passengerLedger(of: alpha), PassengerLedger(released: 12, waiting: 0, arrived: 12, overflowed: 0, abandoned: 0))
        assertConserved(world)
    }

    /// The farthest destination boards first, and for one destination those
    /// who came first; the group that does not fit boards in part, keeping
    /// its minute, and the rest count as refused when the full train leaves.
    func testTheFarthestBoardFirstUpToTheCapacityAndTheRestAreRefused() throws {
        var world = try makeWorld()
        try world.advance(ticks: 0)
        wait(&world, 300, at: alpha, for: beta, .outbound, since: -3)
        wait(&world, 30, at: alpha, for: gamma, .outbound, since: -2)
        wait(&world, 40, at: alpha, for: beta, .outbound, since: -1)
        wait(&world, 50, at: alpha, for: gamma, .outbound, since: -1)

        try world.advance(ticks: 1)
        // Gamma: 30 + 50; then Beta from the earliest: 272 of 300 fit.
        XCTAssertEqual(world.riders(of: one), [riding(alpha, beta, 272), riding(alpha, gamma, 80)])
        XCTAssertEqual(world.riderCount(of: one), 352)
        XCTAssertEqual(world.waitingPassengers(at: alpha), [
            WaitingGroup(line: main, direction: .outbound, destination: beta, since: GameTime(minutes: -3), count: 28),
            WaitingGroup(line: main, direction: .outbound, destination: beta, since: GameTime(minutes: -1), count: 40),
        ])
        // 352 boarding at 8 a second take 44 s: the doors close at 0:52 and
        // the train leaves at 1:01, refusing the 68 then.
        XCTAssertEqual(world.passengerLedger(of: alpha).refused, 0)
        XCTAssertEqual(world.train(id: one)?.times?.closing, GameTime(seconds: 52))
        try world.advance(ticks: 1)
        XCTAssertEqual(world.passengerLedger(of: alpha).refused, 68)
        assertConserved(world)
    }

    /// A full train takes no one at Beta, and every one waiting for it is
    /// refused again; once riders get off there is room.
    func testAFullTrainRefusesEveryoneUntilRidersGetOff() throws {
        var world = try makeWorld()
        wait(&world, 352, at: alpha, for: gamma, .outbound)
        wait(&world, 10, at: beta, for: gamma, .outbound)
        wait(&world, 4, at: gamma, for: beta, .inbound)
        // 352 boarding take 44 s: it leaves Alpha at 1:01, reaches Beta 16 s
        // later and leaves it on time at 1:58, refusing the 10.
        try world.advance(ticks: 2)
        XCTAssertEqual(world.riders(of: one), [riding(alpha, gamma, 352)])
        XCTAssertEqual(world.passengerLedger(of: beta).refused, 10)
        XCTAssertEqual(world.waitingPassengers(at: beta).map(\.count), [10])

        // At Gamma (2:14) the 352 get off, then the train turns round and
        // takes the 4 going back.
        try world.advance(ticks: 1)
        XCTAssertEqual(world.riders(of: one), [riding(gamma, beta, 4)])
        XCTAssertEqual(world.passengerLedger(of: alpha).arrived, 352)
        assertConserved(world)
    }

    /// Only passengers for the train's line, in its direction, for a
    /// station it calls at before it turns round, board.
    func testOnlyTheTrainsLineDirectionAndCallsAheadBoard() throws {
        var world = try makeWorld()
        wait(&world, 3, at: beta, for: alpha, .inbound)
        wait(&world, 4, at: beta, for: gamma, .outbound, line: other)
        wait(&world, 5, at: beta, for: gamma, .outbound)
        try world.advance(ticks: 2)
        XCTAssertEqual(world.riders(of: one), [riding(beta, gamma, 5)])
        XCTAssertEqual(world.waitingPassengers(at: beta).map(\.count), [3, 4])
        XCTAssertEqual(world.passengerLedger(of: beta).refused, 0, "passengers the train would not take are not refused")

        // Back through Beta (4:30–5:30) it takes the 3 for Alpha, and at
        // Alpha (5:46) they get off as the service ends.
        try world.advance(ticks: 3)
        XCTAssertEqual(world.riders(of: one), [riding(beta, alpha, 3)])
        try world.advance(ticks: 1)
        XCTAssertEqual(world.riders, [])
        XCTAssertEqual(world.passengerLedger(of: beta).arrived, 8)
        XCTAssertEqual(world.waitingPassengers(at: beta).map(\.count), [4])
        assertConserved(world)
    }

    /// A pattern train takes only those whose destination it calls at:
    /// those for a skipped stop wait for another train.
    func testAPatternTrainLeavesThoseForAStopItSkips() throws {
        var world = try makeWorld()
        try world.unassignTrain(one)
        _ = try world.addLinePattern(main, calling: [0, 2])
        try world.setLineTrainsInService(main, to: .none)
        try world.setLineTrainsInService(main, to: TrainsInService(peak: 1, offPeak: 1, low: 1), pattern: 0)
        try world.assignTrain(one, to: main, pattern: 0)
        wait(&world, 6, at: alpha, for: beta, .outbound)
        wait(&world, 2, at: alpha, for: gamma, .outbound)
        try world.advance(ticks: 1)
        XCTAssertEqual(world.riders(of: one), [riding(alpha, gamma, 2)])
        XCTAssertEqual(world.waitingPassengers(at: alpha).map(\.count), [6])
    }

    // MARK: - Services that end early

    /// A train taken off its line keeps its riders to their destination but
    /// takes on no one; stopping its service then abandons those still on
    /// board.
    func testATrainOffItsLineCarriesItsRidersButTakesNoOne() throws {
        var world = try makeWorld()
        wait(&world, 5, at: alpha, for: beta, .outbound)
        wait(&world, 7, at: alpha, for: gamma, .outbound)
        wait(&world, 9, at: beta, for: gamma, .outbound)
        try world.advance(ticks: 1)
        try world.unassignTrain(one)
        // At Beta at 0:58 the 5 get off (1:06); the 9 are not taken.
        try world.advance(ticks: 1)
        XCTAssertEqual(world.riders(of: one), [riding(alpha, gamma, 7)])
        XCTAssertEqual(world.waitingPassengers(at: beta).map(\.count), [9])
        XCTAssertEqual(world.passengerLedger(of: beta).refused, 0)

        try world.stopTrainService(one)
        XCTAssertEqual(world.riders, [])
        XCTAssertEqual(world.passengerLedger(of: alpha), PassengerLedger(released: 12, waiting: 0, arrived: 5, overflowed: 0, abandoned: 7))
        assertConserved(world)
    }

    // MARK: - Whole days

    /// With demand at every station, a day of service in one call is the
    /// same as minute by minute, and every minute's counts add up.
    func testADayOfServiceConservesPassengersAndDoesNotDependOnTheBatch() throws {
        var world = try makeWorld()
        for (station, kind) in [(alpha, StationDemandKind.residential), (beta, .shopping), (gamma, .office)] {
            try world.setStationDemand(station, to: StationDemand(kind: kind, dailyTrips: 20_000))
        }
        var stepped = world
        try world.advance(ticks: 1_440)
        for _ in 0..<1_440 {
            try stepped.advance(ticks: 1)
            assertConserved(stepped)
            XCTAssertLessThanOrEqual(stepped.riderCount(of: one), 352)
        }
        XCTAssertEqual(world, stepped)
        XCTAssertGreaterThan(world.passengerLedger(of: alpha).arrived, 0)
        XCTAssertGreaterThan(world.passengerLedger(of: alpha).refused, 0)
    }

    // MARK: - Saving

    func testRidersRoundTripThroughASave() throws {
        var world = try makeWorld()
        wait(&world, 5, at: alpha, for: beta, .outbound)
        wait(&world, 400, at: alpha, for: gamma, .outbound)
        try world.advance(ticks: 1)
        let data = try JSONEncoder().encode(world)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual((json["riders"] as? [[String: Any]])?.count, 1)
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: data), world)

        // No riders, no key; no arrivals or refusals, no keys either.
        var empty = try makeWorld()
        wait(&empty, 1, at: alpha, for: beta, .outbound)
        let emptyJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(empty)) as? [String: Any])
        XCTAssertNil(emptyJSON["riders"])
        let records = try XCTUnwrap(emptyJSON["passengers"] as? [[String: Any]])
        XCTAssertTrue(records.allSatisfy { $0["arrived"] == nil && $0["refused"] == nil })
    }

    func testTheDecoderRejectsRidersThatBreakTheRules() throws {
        var world = try makeWorld()
        wait(&world, 5, at: alpha, for: beta, .outbound)
        wait(&world, 7, at: alpha, for: gamma, .outbound)
        try world.advance(ticks: 1)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(world)) as? [String: Any])
        XCTAssertNoThrow(try decode(json))

        func withRiders(_ change: (inout [[String: Any]]) -> Void) -> [String: Any] {
            var copy = json
            var riders = copy["riders"] as! [[String: Any]]
            change(&riders)
            copy["riders"] = riders
            return copy
        }
        func withGroups(_ change: @escaping (inout [[String: Any]]) -> Void) -> [String: Any] {
            withRiders { riders in
                var groups = riders[0]["groups"] as! [[String: Any]]
                change(&groups)
                riders[0]["groups"] = groups
            }
        }
        let broken: [String: [String: Any]] = [
            "no groups": withGroups { $0 = [] },
            "zero riders": withGroups { $0[0]["count"] = 0 },
            "groups out of order": withGroups { $0.reverse() },
            "riding to where they came from": withGroups { $0[0]["destination"] = 1 },
            "an unknown train": withRiders { $0[0]["train"] = 9 },
            "a train twice": withRiders { $0.append($0[0]) },
            "more than they released": withGroups { $0[0]["count"] = 6 },
            "fewer than they released": withGroups { $0[0]["count"] = 4 },
            "an origin without a record": withGroups { $0[0]["origin"] = 2 },
            "a destination behind the train": withGroups { $0[0]["destination"] = 9 },
            "no riders at all": {
                var copy = json
                copy["riders"] = nil
                return copy
            }(),
        ]
        for (name, value) in broken {
            XCTAssertThrowsError(try decode(value), name)
        }

        // More than the train takes: 353 on one car.
        var full = try makeWorld()
        wait(&full, 352, at: alpha, for: gamma, .outbound)
        try full.advance(ticks: 1)
        var fullJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(full)) as? [String: Any])
        var riders = fullJSON["riders"] as! [[String: Any]]
        var groups = riders[0]["groups"] as! [[String: Any]]
        groups[0]["count"] = 353
        riders[0]["groups"] = groups
        fullJSON["riders"] = riders
        var records = fullJSON["passengers"] as! [[String: Any]]
        records[0]["released"] = 353
        fullJSON["passengers"] = records
        XCTAssertThrowsError(try decode(fullJSON))
    }

    private func decode(_ json: [String: Any]) throws -> GameWorld {
        try JSONDecoder().decode(GameWorld.self, from: JSONSerialization.data(withJSONObject: json))
    }
}
