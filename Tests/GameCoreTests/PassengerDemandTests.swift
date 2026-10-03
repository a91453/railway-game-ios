import Foundation
@testable import GameCore
import XCTest

/// G1a (ARCHITECTURE decision 34): station demand, the trips it derives,
/// their release minute by minute, the stations' queues and the
/// conservation audit. Every expectation here is worked out by hand from the
/// rules.
final class PassengerDemandTests: XCTestCase {
    private let a = StationID(rawValue: 1)
    private let b = StationID(rawValue: 2)
    private let c = StationID(rawValue: 3)
    private let d = StationID(rawValue: 4)

    /// Four point stations in a row, at the centres of tiles (2, 2), (6,
    /// 2), (10, 2) and (14, 2), and a line A–B–C; D is on no line.
    private func makeCorridor() throws -> GameWorld {
        var world = try makeWorld(width: 20, height: 5, balance: 100_000)
        for x in [2, 6, 10, 14] {
            try world.buildStation(named: "S\(x)", at: TestLine.centre(x, 2))
        }
        try world.createLine(named: "Line", stops: [a, b, c])
        world.setSpeed(.normal)
        return world
    }

    private func demand(_ kind: StationDemandKind, _ trips: Int64) -> StationDemand {
        StationDemand(kind: kind, dailyTrips: trips)
    }

    // MARK: - The reference's curves

    /// Every entry of the shape tables is the reference's formula
    /// (`buildStationFlowPresetCurves` with hours 0–23), normalised by
    /// `normalizeStationFlowPresetRowToDailyBase` without a base (scaled
    /// to a mean of 1, clamped to 0...11), in thousandths rounded half up
    /// as `Math.round` does.
    func testTheShapesAreTheReferenceCurvesInThousandths() {
        func g(_ hour: Double, _ mean: Double, _ spread: Double) -> Double {
            let z = (hour - mean) / spread
            return exp(-0.5 * z * z)
        }
        func thousandths(_ curve: (Double) -> Double) -> [Int64] {
            let raw = (0..<24).map { curve(Double($0)) }
            let scale = 24 / raw.reduce(0, +)
            return raw.map { Int64((min(11, max(0, $0 * scale)) * 1000 + 0.5).rounded(.down)) }
        }
        let morning = thousandths { 1 + g($0, 8, 1.15) * 0.6 }
        let evening = thousandths { 1 + g($0, 18, 1.15) * 0.6 }
        XCTAssertEqual(StationDemandKind.residential.departureShape, morning)
        XCTAssertEqual(StationDemandKind.residential.arrivalShape, evening)
        XCTAssertEqual(StationDemandKind.office.departureShape, evening)
        XCTAssertEqual(StationDemandKind.office.arrivalShape, morning)
        XCTAssertEqual(StationDemandKind.shopping.arrivalShape, thousandths { 1 + g($0, 13, 2.4) * 0.42 + g($0, 18, 1.8) * 0.5 })
        XCTAssertEqual(StationDemandKind.shopping.departureShape, thousandths { 1 + g($0, 14, 2.4) * 0.42 + g($0, 19, 1.8) * 0.5 })
        XCTAssertEqual(StationDemandKind.scenic.arrivalShape, thousandths { 1 + g($0, 11, 2.1) * 0.75 })
        XCTAssertEqual(StationDemandKind.scenic.departureShape, thousandths { 1 + g($0, 16, 2.1) * 0.75 })
    }

    /// `PARAMS.PEAK_FACTOR`: 1.5 at 7–9 and 16–19, plus 0.3 at 8 and 18;
    /// `0.6 + 0.02·h` for the other hours of 6–22; 0.1 otherwise.
    func testTheDayShapeIsTheReferencePeakFactor() {
        let expected = (0..<24).map { hour -> Int64 in
            if (7...9).contains(hour) || (16...19).contains(hour) { return hour == 8 || hour == 18 ? 1800 : 1500 }
            if (6...22).contains(hour) { return 600 + 20 * Int64(hour) }
            return 100
        }
        XCTAssertEqual(StationDemand.dayShape, expected)
    }

    // MARK: - Commands

    func testSettingDemandChecksTheStationThenTheTrips() throws {
        var world = try makeCorridor()
        let before = world
        XCTAssertThrowsGameError(try world.setStationDemand(StationID(rawValue: 9), to: demand(.office, -1)), .unknownStation(StationID(rawValue: 9)))
        XCTAssertThrowsGameError(try world.setStationDemand(a, to: demand(.office, -1)), .invalidStationDemand)
        XCTAssertThrowsGameError(try world.setStationDemand(a, to: demand(.office, 1_000_001)), .invalidStationDemand)
        XCTAssertEqual(world, before)

        try world.setStationDemand(a, to: demand(.office, 1_000_000))
        try world.setStationDemand(c, to: demand(.scenic, 0))
        XCTAssertEqual(world.stationDemand(of: a), demand(.office, 1_000_000))
        XCTAssertEqual(world.stationDemand(of: c), demand(.scenic, 0))
        XCTAssertEqual(world.passengers.map(\.station), [a, c])

        // Clearing a demand that never released anyone drops the record.
        try world.setStationDemand(a, to: nil)
        try world.setStationDemand(b, to: nil)
        XCTAssertNil(world.stationDemand(of: a))
        XCTAssertEqual(world.passengers.map(\.station), [c])
        XCTAssertEqual(world.economy.balance, before.economy.balance)
    }

    // MARK: - Trips

    func testATripTakesTheLowestLineAndTheFirstCalls() throws {
        var world = try makeCorridor()
        XCTAssertEqual(world.passengerTrip(from: a, to: c), PassengerTrip(line: LineID(rawValue: 1), direction: .outbound))
        XCTAssertEqual(world.passengerTrip(from: c, to: b), PassengerTrip(line: LineID(rawValue: 1), direction: .inbound))
        XCTAssertNil(world.passengerTrip(from: a, to: a))
        XCTAssertNil(world.passengerTrip(from: a, to: d))

        // Line 2 calls at D, then A, then D again: from D the first call is
        // before A's, so the trip is outbound; line 1 still takes A to C.
        try world.createLine(named: "Loop", stops: [d, a, d, c])
        XCTAssertEqual(world.passengerTrip(from: d, to: a), PassengerTrip(line: LineID(rawValue: 2), direction: .outbound))
        XCTAssertEqual(world.passengerTrip(from: a, to: d), PassengerTrip(line: LineID(rawValue: 2), direction: .inbound))
        XCTAssertEqual(world.passengerTrip(from: a, to: c), PassengerTrip(line: LineID(rawValue: 1), direction: .outbound))
        XCTAssertEqual(world.passengerTrip(from: c, to: d), PassengerTrip(line: LineID(rawValue: 2), direction: .inbound))
    }

    func testLargestRemaindersGoToTheLargestFractionsThenTheLowerIndex() {
        XCTAssertEqual(GameWorld.apportion(10, by: [1, 1, 1]), [4, 3, 3])
        XCTAssertEqual(GameWorld.apportion(2, by: [1, 1, 1]), [1, 1, 0])
        XCTAssertEqual(GameWorld.apportion(7, by: [0, 5, 2]), [0, 5, 2])
        // Quotas 1.2, 3.6, 2.4 and 0.8: 1, 3 and 2 whole, and the 2 left go
        // to the fractions .8 and .6.
        XCTAssertEqual(GameWorld.apportion(8, by: [3, 9, 6, 2]), [1, 4, 2, 1])
        XCTAssertEqual(GameWorld.apportion(5, by: [0, 0]), [0, 0])
        XCTAssertEqual(GameWorld.apportion(0, by: [4, 1]), [0, 0])
    }

    /// A starts 1000 a day, B 3000 and C 1000: A shares its 1000 between B
    /// and C as 3000 : 1000, B its 3000 between A and C evenly, C its 1000
    /// between A and B as 1000 : 3000. D, on no line, gets nothing and
    /// sends nothing.
    func testDailyTripsAreSharedByTheDestinationsOwnTrips() throws {
        var world = try makeCorridor()
        try world.setStationDemand(a, to: demand(.residential, 1_000))
        try world.setStationDemand(b, to: demand(.office, 3_000))
        try world.setStationDemand(c, to: demand(.office, 1_000))
        try world.setStationDemand(d, to: demand(.shopping, 5_000))
        XCTAssertEqual([b, c, d].map { world.dailyDemand(from: a, to: $0) }, [750, 250, 0])
        XCTAssertEqual([a, c, d].map { world.dailyDemand(from: b, to: $0) }, [1_500, 1_500, 0])
        XCTAssertEqual([a, b, d].map { world.dailyDemand(from: c, to: $0) }, [250, 750, 0])
        XCTAssertEqual([a, b, c].map { world.dailyDemand(from: d, to: $0) }, [0, 0, 0])

        // Without demand of its own a station draws nothing.
        try world.setStationDemand(c, to: nil)
        XCTAssertEqual(world.dailyDemand(from: a, to: b), 1_000)
        XCTAssertEqual(world.dailyDemand(from: a, to: c), 0)
    }

    func testHourlyTripsAddUpToTheDayAndFollowTheShapes() throws {
        var world = try makeCorridor()
        try world.setStationDemand(a, to: demand(.residential, 1))
        try world.setStationDemand(b, to: demand(.office, 1))
        // One trip a day goes to the heaviest hour: 08:00, where the day,
        // the home's departures and the office's arrivals all peak.
        var expected = Array(repeating: Int64(0), count: 24)
        expected[8] = 1
        XCTAssertEqual(world.hourlyDemand(from: a, to: b), expected)
        // The way back peaks at 18:00.
        expected = Array(repeating: 0, count: 24)
        expected[18] = 1
        XCTAssertEqual(world.hourlyDemand(from: b, to: a), expected)

        try world.setStationDemand(a, to: demand(.residential, 999_983))
        let hourly = world.hourlyDemand(from: a, to: b)
        XCTAssertEqual(hourly.reduce(0, +), 999_983)
        XCTAssertEqual(hourly.firstIndex(of: hourly.max()!), 8)
        XCTAssertEqual(world.hourlyDemand(from: a, to: d), Array(repeating: 0, count: 24))
    }

    // MARK: - Release

    /// One trip a day, all in hour 8: minute `m` of hour 7 adds `m`
    /// 3600ths (1770 by 07:59), minute `m` of hour 8 adds `60 − m`, and the
    /// 3600th is reached at 08:59 exactly, when the passenger is released
    /// and the remainder is back to 0.
    func testOneTripIsReleasedWhenItsInterpolatedShareAddsUpToAWholePassenger() throws {
        var world = try makeCorridor()
        try world.setStationDemand(a, to: demand(.residential, 1))
        try world.setStationDemand(b, to: demand(.office, 1))
        try world.advance(ticks: 7 * 60)
        XCTAssertTrue(world.waitingPassengers(at: a).isEmpty)
        XCTAssertTrue(world.passengers[0].remainders.isEmpty)
        try world.advance(ticks: 60)
        XCTAssertEqual(world.passengers[0].remainders, [DemandRemainder(destination: b, value: 1_770)])
        try world.advance(ticks: 59)
        XCTAssertEqual(world.passengers[0].remainders, [DemandRemainder(destination: b, value: 3_599)])
        XCTAssertTrue(world.waitingPassengers(at: a).isEmpty)
        try world.advance(ticks: 1)
        XCTAssertEqual(
            world.waitingPassengers(at: a),
            [WaitingGroup(line: LineID(rawValue: 1), direction: .outbound, destination: b, since: GameTime(minutes: 539), count: 1)]
        )
        XCTAssertTrue(world.passengers[0].remainders.isEmpty)
        XCTAssertEqual(world.passengerLedger(of: a), PassengerLedger(released: 1, waiting: 1, overflowed: 0, abandoned: 0))
    }

    /// Any 1440 minutes in a row release every pair's daily trips exactly,
    /// wherever they start, and leave the remainders as they found them.
    func testAnyDayReleasesExactlyTheDailyTrips() throws {
        for start in [Int64(0), 777, 1_439] {
            var world = try makeCorridor()
            world.setSpeed(.normal)
            try world.setStationDemand(a, to: demand(.residential, 900))
            try world.setStationDemand(b, to: demand(.office, 600))
            try world.setStationDemand(c, to: demand(.shopping, 300))
            try world.advance(ticks: Int(start))
            let before = world.passengers.map { ($0.released, $0.remainders) }
            try world.advance(ticks: 1_440)
            for (index, record) in world.passengers.enumerated() {
                let daily = [a, b, c].reduce(Int64(0)) { $0 + world.dailyDemand(from: record.station, to: $1) }
                XCTAssertEqual(record.released - before[index].0, daily, "start \(start), station \(record.station.rawValue)")
                XCTAssertEqual(record.remainders, before[index].1, "start \(start)")
                let ledger = world.passengerLedger(of: record.station)
                XCTAssertEqual(ledger.released, ledger.waiting + ledger.overflowed + ledger.abandoned)
            }
            XCTAssertEqual(world.passengers.map(\.released).reduce(0, +) - before.map(\.0).reduce(0, +), 1_800)
        }
    }

    /// Passengers join the back of the queue: by minute, then by origin
    /// and destination within the minute.
    func testGroupsQueueInTheOrderTheyWereReleased() throws {
        var world = try makeCorridor()
        try world.setStationDemand(a, to: demand(.residential, 20_000))
        try world.setStationDemand(b, to: demand(.office, 20_000))
        try world.setStationDemand(c, to: demand(.office, 20_000))
        try world.advance(ticks: 8 * 60)
        let groups = world.waitingPassengers(at: a)
        XCTAssertFalse(groups.isEmpty)
        for (earlier, later) in zip(groups, groups.dropFirst()) {
            XCTAssertTrue(earlier.since < later.since || (earlier.since == later.since && earlier.destination < later.destination))
        }
        XCTAssertTrue(groups.allSatisfy { $0.line == LineID(rawValue: 1) && $0.direction == .outbound && $0.count >= 1 })
        XCTAssertEqual(groups.reduce(0) { $0 + $1.count }, world.passengerLedger(of: a).waiting)
    }

    /// A station holds 4000 waiting passengers: the group that would pass
    /// that gets in up to it, and the rest leave at once.
    func testAFullStationTurnsPassengersAway() throws {
        var world = try makeCorridor()
        try world.setStationDemand(a, to: demand(.residential, 1_000_000))
        try world.setStationDemand(b, to: demand(.office, 1_000_000))
        try world.advance(ticks: 1_440)
        let ledger = world.passengerLedger(of: a)
        XCTAssertEqual(ledger.waiting, 4_000)
        XCTAssertEqual(ledger.released, 1_000_000)
        XCTAssertEqual(ledger.overflowed, 996_000)
        XCTAssertEqual(ledger.abandoned, 0)
    }

    /// Doing the same in one call or one minute at a time gives the same
    /// world: the release phase runs in the steps the clock skips.
    func testReleasingInOneCallOrMinuteByMinuteIsTheSame() throws {
        var world = try makeCorridor()
        try world.setStationDemand(a, to: demand(.residential, 5_000))
        try world.setStationDemand(b, to: demand(.office, 3_000))
        try world.setStationDemand(c, to: demand(.scenic, 2_000))
        var stepped = world
        try world.advance(ticks: 2_000)
        for _ in 0..<2_000 {
            try stepped.advance(ticks: 1)
        }
        XCTAssertEqual(world, stepped)
        world.setSpeed(.double)
        stepped.setSpeed(.normal)
        try world.advance(ticks: 300)
        try stepped.advance(ticks: 600)
        stepped.setSpeed(.double)
        XCTAssertEqual(world, stepped)
    }

    // MARK: - Lines change

    func testPassengersWhoseLineNoLongerTakesThemLeave() throws {
        var world = try makeCorridor()
        try world.createLine(named: "Back", stops: [c, b, a])
        try world.setStationDemand(a, to: demand(.residential, 20_000))
        try world.setStationDemand(b, to: demand(.office, 20_000))
        try world.setStationDemand(c, to: demand(.office, 20_000))
        try world.advance(ticks: 9 * 60)
        let waitingAtA = world.passengerLedger(of: a).waiting
        let groupsAtB = world.waitingPassengers(at: b)
        XCTAssertGreaterThan(waitingAtA, 0)

        // Line 1 without B: A's passengers for C keep their trip; those for
        // B, and B's for A and C, have lost theirs (line 2 takes B's now,
        // but they waited for line 1).
        try world.setLineStops(LineID(rawValue: 1), to: [a, c])
        let groupsAtA = world.waitingPassengers(at: a)
        XCTAssertFalse(groupsAtA.isEmpty)
        XCTAssertTrue(groupsAtA.allSatisfy { $0.destination == c })
        XCTAssertTrue(world.waitingPassengers(at: b).isEmpty)
        XCTAssertEqual(world.passengerLedger(of: b).abandoned, groupsAtB.reduce(0) { $0 + $1.count })
        let atA = world.passengerLedger(of: a)
        XCTAssertEqual(atA.waiting + atA.abandoned, waitingAtA)

        // Reversed, line 1 takes A to C inbound: the outbound groups leave.
        try world.setLineStops(LineID(rawValue: 1), to: [c, a])
        XCTAssertTrue(world.waitingPassengers(at: a).isEmpty)
        XCTAssertEqual(world.passengerLedger(of: a).abandoned, waitingAtA)

        // From now on B's trips take line 2; removing it strands them.
        try world.advance(ticks: 60)
        XCTAssertTrue(world.waitingPassengers(at: b).allSatisfy { $0.line == LineID(rawValue: 2) })
        let waitingAtB = world.passengerLedger(of: b).waiting
        XCTAssertGreaterThan(waitingAtB, 0)
        try world.removeLine(LineID(rawValue: 2))
        XCTAssertTrue(world.waitingPassengers(at: b).isEmpty)
        XCTAssertEqual(world.passengerLedger(of: b).abandoned, groupsAtB.reduce(0) { $0 + $1.count } + waitingAtB)
        for record in world.passengers {
            XCTAssertEqual(record.released, record.waitingCount + record.overflowed + record.abandoned)
        }
    }

    func testClearingDemandKeepsWhoIsWaiting() throws {
        var world = try makeCorridor()
        try world.setStationDemand(a, to: demand(.residential, 20_000))
        try world.setStationDemand(b, to: demand(.office, 20_000))
        try world.advance(ticks: 9 * 60)
        let waiting = world.waitingPassengers(at: a)
        try world.setStationDemand(a, to: nil)
        XCTAssertEqual(world.waitingPassengers(at: a), waiting)
        XCTAssertNil(world.stationDemand(of: a))
        // B has no destination now, and A releases nothing more.
        let before = world.passengers
        try world.advance(ticks: 120)
        XCTAssertEqual(world.passengers, before)
    }

    // MARK: - Saves

    func testAWorldWithoutPassengersSavesAsBefore() throws {
        let world = try makeCorridor()
        let json = String(decoding: try JSONEncoder().encode(world), as: UTF8.self)
        XCTAssertFalse(json.contains("passengers"))
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: Data(json.utf8)), world)
    }

    func testPassengersRoundTripThroughASave() throws {
        var world = try makeCorridor()
        try world.setStationDemand(a, to: demand(.residential, 30_000))
        try world.setStationDemand(b, to: demand(.office, 30_000))
        try world.setStationDemand(c, to: demand(.scenic, 7))
        try world.advance(ticks: 500)
        try world.setLineStops(LineID(rawValue: 1), to: [a, c])
        let restored = try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world))
        XCTAssertEqual(restored, world)
        XCTAssertEqual(restored.passengers.map(\.waitingCount), world.passengers.map(\.waitingCount))
        var continued = world
        var reloaded = restored
        try continued.advance(ticks: 1_000)
        try reloaded.advance(ticks: 1_000)
        XCTAssertEqual(continued, reloaded)
    }

    func testTheDecoderRejectsPassengersThatBreakTheRules() throws {
        var world = try makeCorridor()
        try world.setStationDemand(a, to: demand(.residential, 30_000))
        try world.setStationDemand(b, to: demand(.office, 30_000))
        try world.setStationDemand(c, to: demand(.office, 30_000))
        try world.advance(ticks: 500)
        let saved = try JSONSerialization.jsonObject(with: JSONEncoder().encode(world)) as! [String: Any]
        XCTAssertNoThrow(try decode(saved))

        func mutated(_ change: (inout [[String: Any]]) -> Void) -> [String: Any] {
            var copy = saved
            var records = copy["passengers"] as! [[String: Any]]
            change(&records)
            copy["passengers"] = records
            return copy
        }
        func firstGroup(_ change: @escaping (inout [String: Any]) -> Void) -> [String: Any] {
            mutated { records in
                var groups = records[0]["waiting"] as! [[String: Any]]
                change(&groups[0])
                records[0]["waiting"] = groups
            }
        }
        let broken: [(String, [String: Any])] = [
            ("released does not add up", mutated { $0[0]["released"] = ($0[0]["released"] as! Int) + 1 }),
            ("negative overflow", mutated { $0[0]["overflowed"] = -1 }),
            ("a group of none", firstGroup { $0["count"] = 0 }),
            ("a group for a line that does not exist", firstGroup { $0["line"] = 7 }),
            ("a group the line takes the other way", firstGroup { $0["direction"] = "inbound" }),
            ("a group for its own station", firstGroup { $0["destination"] = 1 }),
            ("a group from the future", firstGroup { $0["since"] = 501 }),
            ("a group from a minute not yet released", mutated { records in
                var groups = records[0]["waiting"] as! [[String: Any]]
                groups[groups.count - 1]["since"] = 500
                records[0]["waiting"] = groups
            }),
            ("groups out of order", mutated { records in
                let groups = records[0]["waiting"] as! [[String: Any]]
                records[0]["waiting"] = Array(groups.reversed())
            }),
            ("groups of one minute out of order", mutated { records in
                var groups = records[0]["waiting"] as! [[String: Any]]
                let pair = groups.indices.dropLast().first { groups[$0]["since"] as! Int == groups[$0 + 1]["since"] as! Int }!
                groups.swapAt(pair, pair + 1)
                records[0]["waiting"] = groups
            }),
            ("a group twice in one minute", mutated { records in
                var groups = records[0]["waiting"] as! [[String: Any]]
                groups.insert(groups[0], at: 1)
                records[0]["released"] = (records[0]["released"] as! Int) + (groups[0]["count"] as! Int)
                records[0]["waiting"] = groups
            }),
            ("more released than a station can count", mutated { records in
                records[0]["released"] = (records[0]["released"] as! Int) - (records[0]["overflowed"] as! Int) + (1 << 62)
                records[0]["overflowed"] = 1 << 62
            }),
            ("a remainder of a whole passenger", mutated { $0[0]["remainders"] = [["destination": 2, "value": 3_600]] }),
            ("a remainder for itself", mutated { $0[0]["remainders"] = [["destination": 1, "value": 5]] }),
            ("a remainder for a missing station", mutated { $0[0]["remainders"] = [["destination": 9, "value": 5]] }),
            ("records out of order", mutated { $0.reverse() }),
            ("a record of a missing station", mutated { $0[1]["station"] = 9 }),
            ("a record with nothing in it", mutated { $0.append(["station": 4, "waiting": [], "released": 0, "overflowed": 0, "abandoned": 0, "remainders": []]) }),
            ("an explicit null demand", mutated { $0[0]["demand"] = NSNull() }),
            ("too many trips a day", mutated { $0[0]["demand"] = ["kind": "office", "dailyTrips": 1_000_001] }),
            ("an unknown kind", mutated { $0[0]["demand"] = ["kind": "airport", "dailyTrips": 1] }),
        ]
        for (name, json) in broken {
            XCTAssertThrowsError(try decode(json), name)
        }
    }

    /// The plan kept between calls is always the one the world would work
    /// out now: every command that changes demand or lines forgets it.
    func testTheKeptPlanFollowsEveryChange() throws {
        var world = try makeCorridor()
        func expectCurrent(_ step: String, file: StaticString = #filePath, line: UInt = #line) {
            let kept = world.passengerPlan.plan.flatMap { $0 }
            let fresh = world.makePassengerPlan()
            XCTAssertEqual(kept?.flows.map(\.destination), fresh?.flows.map(\.destination), step, file: file, line: line)
            XCTAssertEqual(kept?.flows.map(\.trip), fresh?.flows.map(\.trip), step, file: file, line: line)
            XCTAssertEqual(kept?.flows.map(\.record), fresh?.flows.map(\.record), step, file: file, line: line)
            XCTAssertEqual(kept?.hourly, fresh?.hourly, step, file: file, line: line)
        }
        try world.setStationDemand(a, to: demand(.residential, 5_000))
        try world.setStationDemand(b, to: demand(.office, 3_000))
        try world.advance(ticks: 30)
        expectCurrent("demand")
        try world.setStationDemand(d, to: demand(.scenic, 2_000))
        try world.advance(ticks: 30)
        expectCurrent("demand of a station on no line")
        try world.createLine(named: "Spur", stops: [b, d])
        try world.advance(ticks: 30)
        expectCurrent("a new line")
        try world.setLineStops(LineID(rawValue: 2), to: [d, a])
        try world.advance(ticks: 30)
        expectCurrent("new stops")
        try world.removeLine(LineID(rawValue: 1))
        try world.advance(ticks: 30)
        expectCurrent("a removed line")
        try world.setStationDemand(a, to: nil)
        try world.advance(ticks: 30)
        expectCurrent("demand cleared")
        // A world that keeps a plan equals one that does not, and a loaded
        // world works its own out.
        let loaded = try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world))
        XCTAssertTrue(loaded.passengerPlan.plan == nil)
        XCTAssertEqual(loaded, world)
    }

    private func decode(_ json: [String: Any]) throws -> GameWorld {
        try JSONDecoder().decode(GameWorld.self, from: JSONSerialization.data(withJSONObject: json))
    }
}
