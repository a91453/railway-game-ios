import Foundation
@testable import GameCore
import XCTest

final class PassengerTransferTests: XCTestCase {
    private let a = StationID(rawValue: 1)
    private let b = StationID(rawValue: 2)
    private let c = StationID(rawValue: 3)

    private func world() throws -> GameWorld {
        var world = try makeWorld(width: 8_192, height: 4_096, balance: 1_000_000)
        let track = TestLine(tiles: 7)
        try track.build(in: &world)
        for (name, x) in [("A", 1), ("B", 3), ("C", 5)] {
            try track.buildStation(named: name, beside: x, at: 1, in: &world)
        }
        let first = try world.createLine(named: "First", stops: [a, b]).id
        let second = try world.createLine(named: "Second", stops: [b, c]).id
        for line in [first, second] {
            try world.setLineServiceWindow(line, to: .allDay)
            try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        }
        let one = try world.purchaseTrain(named: "One").id
        let two = try world.purchaseTrain(named: "Two").id
        try world.placeTrain(one, at: track.at(1, facingEast: true))
        try world.placeTrain(two, at: track.at(3, facingEast: true))
        try world.setTrainMovementRate(one, to: 1024)
        try world.setTrainMovementRate(two, to: 1024)
        try world.assignTrain(one, to: first)
        try world.assignTrain(two, to: second)
        try world.setStationDemand(a, to: StationDemand(kind: .residential, dailyTrips: 0))
        world.setPassengerRoutingMode(.network)
        world.setSpeed(.normal)
        return world
    }

    func testPassengerChangesTrainsAndOriginLedgerStaysConserved() throws {
        var world = try world()
        let route = try XCTUnwrap(world.passengerRoutes(from: a, to: c).first)
        XCTAssertEqual(route.legs.map(\.from), [a, b])
        let journey = try XCTUnwrap(PassengerJourney(origin: a, route: route))
        let origin = try XCTUnwrap(world.passengers.firstIndex { $0.station == a })
        world.passengers[origin].release(5, along: journey, at: world.clock.now)

        try world.advance(ticks: 1)
        XCTAssertEqual(world.riders(of: TrainID(rawValue: 1)).map(\.count), [5])
        try world.advance(ticks: 1)
        XCTAssertEqual(world.riders(of: TrainID(rawValue: 1)), [])
        let transfer = try XCTUnwrap(world.waitingPassengers(at: b).first)
        XCTAssertEqual(transfer.journey?.origin, a)
        XCTAssertEqual(transfer.journey?.current, 1)
        XCTAssertEqual(transfer.count, 5)
        XCTAssertGreaterThan(transfer.readyAt!, world.clock.now)
        XCTAssertEqual(world.passengerLedger(of: a).waiting, 5)

        var loaded = try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world))
        try world.advance(ticks: 15)
        for _ in 0..<15 { try loaded.advance(ticks: 1) }
        XCTAssertEqual(world, loaded)
        let ledger = world.passengerLedger(of: a)
        XCTAssertEqual(ledger.released, 5)
        XCTAssertEqual(ledger.arrived, 5)
        XCTAssertEqual(ledger.waiting + ledger.riding + ledger.overflowed + ledger.abandoned, 0)
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world)), world)
    }

    func testNetworkDemandUsesRoutesAndBatchMatchesMinuteSteps() throws {
        var batched = try world()
        try batched.setStationDemand(a, to: StationDemand(kind: .residential, dailyTrips: 1_000))
        try batched.setStationDemand(c, to: StationDemand(kind: .office, dailyTrips: 1_000))
        var stepped = batched

        try batched.advance(ticks: 30)
        for _ in 0..<30 { try stepped.advance(ticks: 1) }
        XCTAssertEqual(batched, stepped)
        let ledger = batched.passengerLedger(of: a)
        XCTAssertGreaterThan(ledger.released, 0)
        XCTAssertEqual(ledger.released,
            ledger.waiting + ledger.riding + ledger.arrived + ledger.overflowed + ledger.abandoned)
        XCTAssertTrue(batched.passengers.flatMap(\.waiting).allSatisfy { $0.journey != nil })
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(batched)), batched)
    }

    private func assertConservedAndSaveable(_ world: GameWorld, file: StaticString = #filePath, line: UInt = #line) throws {
        for station in world.stations {
            let ledger = world.passengerLedger(of: station.id)
            XCTAssertEqual(ledger.released,
                ledger.waiting + ledger.riding + ledger.arrived + ledger.overflowed + ledger.abandoned,
                file: file, line: line)
        }
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world)), world,
                       file: file, line: line)
    }

    func testMultipleRoutesReleasedInTheSameMinuteSurviveSaving() throws {
        var world = try world()
        let alternate = try world.createLine(named: "Alternate", stops: [a, b]).id
        try world.setLineServiceWindow(alternate, to: .allDay)
        try world.setLineTrainsInService(alternate, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        for train in world.trains { try world.unassignTrain(train.id) }
        try world.setStationDemand(a, to: StationDemand(kind: .residential, dailyTrips: 100_000))
        try world.setStationDemand(c, to: StationDemand(kind: .office, dailyTrips: 100_000))

        try world.advance(ticks: 1)
        let waiting = world.waitingPassengers(at: a)
        XCTAssertEqual(Set(waiting.map(\.line)).count, 2)
        XCTAssertEqual(Set(waiting.map(\.destination)), [b])
        try assertConservedAndSaveable(world)
    }

    func testBatchMatchesMinuteStepsAcrossOpeningAndClosingWindows() throws {
        for window in [ServiceWindow.hours(open: 2, close: 6), .hours(open: 0, close: 5)] {
            var batched = try world()
            for train in batched.trains { try batched.unassignTrain(train.id) }
            try batched.setLineServiceWindow(LineID(rawValue: 2), to: window)
            try batched.setStationDemand(a, to: StationDemand(kind: .residential, dailyTrips: 100_000))
            try batched.setStationDemand(c, to: StationDemand(kind: .office, dailyTrips: 100_000))
            var stepped = batched
            try batched.advance(ticks: 10)
            for _ in 0..<10 { try stepped.advance(ticks: 1) }
            XCTAssertEqual(batched, stepped, "\(window)")
            XCTAssertGreaterThan(batched.passengerLedger(of: a).released, 0)
            try assertConservedAndSaveable(batched)
        }
    }

    func testBatchMatchesMinuteStepsAcrossServiceLevelChanges() throws {
        var batched = try world()
        for train in batched.trains { try batched.unassignTrain(train.id) }
        try batched.setLineTrainsInService(LineID(rawValue: 2), to: TrainsInService(peak: 1, offPeak: 0, low: 0))
        try batched.setServiceDay(ServiceDay(bands: [.init(start: 0, level: .low),
            .init(start: 2, level: .peak), .init(start: 6, level: .offPeak)]))
        try batched.setStationDemand(a, to: StationDemand(kind: .residential, dailyTrips: 100_000))
        try batched.setStationDemand(c, to: StationDemand(kind: .office, dailyTrips: 100_000))
        var stepped = batched
        try batched.advance(ticks: 10)
        for _ in 0..<10 { try stepped.advance(ticks: 1) }
        XCTAssertEqual(batched, stepped)
        XCTAssertGreaterThan(batched.passengerLedger(of: a).released, 0)
        try assertConservedAndSaveable(batched)
    }

    func testTransferOverflowIsChargedToTheOriginalStation() throws {
        var world = try world()
        let journey = try XCTUnwrap(PassengerJourney(origin: a, route: XCTUnwrap(world.passengerRoutes(from: a, to: c).first)))
        world.passengers[0].release(5, along: journey, at: world.clock.now)
        try world.advance(ticks: 1)
        try world.setStationDemand(b, to: StationDemand(kind: .office, dailyTrips: 0))
        let index = try XCTUnwrap(world.passengers.firstIndex { $0.station == b })
        world.passengers[index].release(3_998, to: c,
            along: PassengerTrip(line: LineID(rawValue: 2), direction: .outbound), at: world.clock.now)

        try world.advance(ticks: 1)
        XCTAssertEqual(world.passengerLedger(of: a).waiting, 2)
        XCTAssertEqual(world.passengerLedger(of: a).abandoned, 3)
        XCTAssertEqual(world.passengerLedger(of: b).released, 3_998)
        XCTAssertEqual(world.passengerLedger(of: b).abandoned, 0)
        try assertConservedAndSaveable(world)
    }

    func testRemovingTheNextLineAbandonsWaitingJourneysAtTheirOrigin() throws {
        var world = try world()
        let journey = try XCTUnwrap(PassengerJourney(origin: a, route: XCTUnwrap(world.passengerRoutes(from: a, to: c).first)))
        world.passengers[0].release(5, along: journey, at: GameTime(minutes: -1))
        try world.removeLine(LineID(rawValue: 2))
        XCTAssertEqual(world.passengerLedger(of: a).abandoned, 5)
        XCTAssertEqual(world.passengerLedger(of: a).waiting, 0)
        try assertConservedAndSaveable(world)
    }

    func testRemovingAPatternAbandonsItsQueueAndPreservesLaterPatternIdentity() throws {
        var world = try world()
        let line = try world.createLine(named: "Patterns", stops: [a, b, c]).id
        try world.setLineServiceWindow(line, to: .allDay)
        let first = try world.addLinePattern(line, calling: [0, 1, 2])
        let later = try world.addLinePattern(line, calling: [0, 2])
        for pattern in [first, later] {
            try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1), pattern: pattern)
        }
        let routes = world.passengerRoutes(from: a, to: c)
        let oldFirst = try XCTUnwrap(routes.first { $0.legs.count == 1 && $0.legs[0].pattern == first })
        let oldLater = try XCTUnwrap(routes.first { $0.legs.count == 1 && $0.legs[0].pattern == later })
        world.passengers[0].release(5, along: try XCTUnwrap(PassengerJourney(origin: a, route: oldFirst)), at: GameTime(minutes: -1))
        world.passengers[0].release(7, along: try XCTUnwrap(PassengerJourney(origin: a, route: oldLater)), at: GameTime(minutes: -1))

        try world.removeLinePattern(line, at: first)
        XCTAssertEqual(world.passengerLedger(of: a).abandoned, 5)
        XCTAssertEqual(world.waitingPassengers(at: a).first?.journey?.leg.pattern, 0)
        XCTAssertEqual(world.passengerLedger(of: a).waiting, 7)
        try assertConservedAndSaveable(world)
    }

    func testBreakingTheTrackAbandonsThePlannedQueue() throws {
        var world = try world()
        let journey = try XCTUnwrap(PassengerJourney(origin: a, route: XCTUnwrap(world.passengerRoutes(from: a, to: c).first)))
        world.passengers[0].release(5, along: journey, at: GameTime(minutes: -1))
        try world.removeTrackPlatform(a, on: .edge(2), from: 0)
        try world.removeTrackEdge(.edge(2))
        XCTAssertEqual(world.passengerLedger(of: a).abandoned, 5)
        try assertConservedAndSaveable(world)
    }

    func testStoppingATrainAbandonsItsRidersOnTheOriginalLedger() throws {
        var world = try world()
        let journey = try XCTUnwrap(PassengerJourney(origin: a, route: XCTUnwrap(world.passengerRoutes(from: a, to: c).first)))
        world.passengers[0].release(5, along: journey, at: world.clock.now)
        try world.advance(ticks: 1)
        let train = TrainID(rawValue: 1)
        try world.unassignTrain(train)
        try world.stopTrainService(train)
        XCTAssertEqual(world.passengerLedger(of: a).abandoned, 5)
        try assertConservedAndSaveable(world)
    }

    func testReverseTransferArrivesAndFaresAreChargedOnlyOnce() throws {
        var world = try world()
        world.setEconomyMode(.management)
        try world.setStationDemand(c, to: StationDemand(kind: .office, dailyTrips: 0))
        let journey = try XCTUnwrap(PassengerJourney(origin: c, route: XCTUnwrap(world.passengerRoutes(from: c, to: a).first)))
        XCTAssertEqual(journey.legs.map(\.direction), [.inbound, .inbound])
        let index = try XCTUnwrap(world.passengers.firstIndex { $0.station == c })
        world.passengers[index].release(5, along: journey, at: world.clock.now)
        try world.advance(ticks: 30)
        XCTAssertEqual(world.passengerLedger(of: c).arrived, 5)
        XCTAssertEqual(world.accounts.pending.fareTrips, 5)
        let expected = GameWorld.wholeDollars(5 * (try XCTUnwrap(world.tripFare(from: c, to: a))).amount)
        XCTAssertEqual(world.accounts.pending.fareRevenue, expected)
        try assertConservedAndSaveable(world)
    }

    func testTurningOffAllPlannedServiceAbandonsTransfers() throws {
        var world = try world()
        let journey = try XCTUnwrap(PassengerJourney(origin: a, route: XCTUnwrap(world.passengerRoutes(from: a, to: c).first)))
        world.passengers[0].release(5, along: journey, at: world.clock.now)
        try world.advance(ticks: 2)
        try world.setLineTrainsInService(LineID(rawValue: 2), to: .none)
        XCTAssertEqual(world.passengerLedger(of: a).abandoned, 5)
        XCTAssertEqual(world.passengerLedger(of: a).waiting, 0)
        XCTAssertEqual(world.waitingPassengers(at: b), [])
        try assertConservedAndSaveable(world)
    }

    func testRouteCreditsAreFairAtMaximumDemandAndIndependentOfReleaseChunks() throws {
        let world = try world()
        let journey = try XCTUnwrap(PassengerJourney(origin: a, route: XCTUnwrap(world.passengerRoutes(from: a, to: c).first)))
        // The credit algorithm depends only on weights; journey identity
        // is exercised by the world save/continuation test below.
        var batched = PassengerRouteBalance(origin: a, destination: c,
            journeys: [journey, journey, journey], weights: [5, 3, 2], balances: [0, 0, 0])
        var stepped = batched
        let million = StationDemand.maximumDailyTrips
        XCTAssertEqual(batched.allocate(million), [500_000, 300_000, 200_000])
        var shares: [Int64] = [0, 0, 0]
        var remaining = million
        for count in [Int64(1), 7, 113, 10_001, million - 10_122] {
            let allocated = stepped.allocate(count)
            for index in shares.indices { shares[index] += allocated[index] }
            remaining -= count
        }
        XCTAssertEqual(remaining, 0)
        XCTAssertEqual(shares, [500_000, 300_000, 200_000])
        XCTAssertEqual(batched, stepped)
        XCTAssertEqual(stepped.balances, [0, 0, 0])
        var oneAtATime = PassengerRouteBalance(origin: a, destination: c,
            journeys: [journey, journey], weights: [1, 1], balances: [0, 0])
        XCTAssertEqual(oneAtATime.allocate(1), [1, 0])
        XCTAssertEqual(oneAtATime.allocate(1), [0, 1])
    }

    func testMultipleRouteCreditsSurviveSavingAndServiceOptionChanges() throws {
        var world = try world()
        for train in world.trains { try world.unassignTrain(train.id) }
        for headway in [Int64(6), 8, 10] {
            let line = try world.createLine(named: "Direct \(headway)", stops: [a, c]).id
            try world.setLineServiceWindow(line, to: .allDay)
            try world.setLineTargetHeadways(line, to: TargetHeadways(peak: headway, offPeak: headway, low: headway))
        }
        try world.setStationDemand(a, to: StationDemand(kind: .residential, dailyTrips: StationDemand.maximumDailyTrips))
        try world.setStationDemand(c, to: StationDemand(kind: .office, dailyTrips: StationDemand.maximumDailyTrips))
        try world.advance(ticks: 17)
        XCTAssertEqual(world.passengerRouteBalances.first?.journeys.count, 3)
        var loaded = try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world))
        try world.advance(ticks: 103)
        for _ in 0..<103 { try loaded.advance(ticks: 1) }
        XCTAssertEqual(world, loaded)
        XCTAssertGreaterThan(world.passengerLedger(of: a).overflowed, 0)
        try world.removeLine(LineID(rawValue: 4))
        try world.advance(ticks: 1)
        XCTAssertFalse(world.passengerRouteBalances.flatMap(\.journeys).flatMap(\.legs).contains { $0.line == LineID(rawValue: 4) })
        try assertConservedAndSaveable(world)
    }

    func testAPlannedPassengerDoesNotBoardTheWrongPattern() throws {
        var world = try world()
        let first = LineID(rawValue: 1)
        let journey = try XCTUnwrap(PassengerJourney(origin: a, route: XCTUnwrap(world.passengerRoutes(from: a, to: c).first)))
        let pattern = try world.addLinePattern(first, calling: [0, 1])
        try world.setLineTrainsInService(first, to: TrainsInService(peak: 1, offPeak: 1, low: 1), pattern: pattern)
        try world.unassignTrain(TrainID(rawValue: 1))
        try world.assignTrain(TrainID(rawValue: 1), to: first, pattern: pattern)
        world.passengers[0].release(5, along: journey, at: world.clock.now)
        try world.advance(ticks: 1)
        XCTAssertEqual(world.riderCount(of: TrainID(rawValue: 1)), 0)
        XCTAssertEqual(world.passengerLedger(of: a).waiting, 5)
        try assertConservedAndSaveable(world)
    }

    func testAPlannedPassengerDoesNotBoardAnOldTimetableMissingTheirStop() throws {
        var world = try world()
        world.setSpeed(.x10)
        try world.advance(ticks: 8)
        try world.setLineStops(LineID(rawValue: 1), to: [a, c])
        let journey = try XCTUnwrap(PassengerJourney(origin: a, route: XCTUnwrap(world.passengerRoutes(from: a, to: c).first)))
        XCTAssertEqual(journey.legs.map(\.to), [c])
        world.passengers[0].release(5, along: journey, at: world.clock.now)
        try world.advance(ticks: 1)
        XCTAssertEqual(world.riderCount(of: TrainID(rawValue: 1)), 0)
        XCTAssertEqual(world.passengerLedger(of: a).waiting, 5)
        try assertConservedAndSaveable(world)
    }

    func testDemandAcrossMidnightAndOvernightServiceMatchesMinuteSteps() throws {
        var batched = try world()
        for train in batched.trains { try batched.unassignTrain(train.id) }
        try batched.advance(ticks: 1_438)
        try batched.setLineServiceWindow(LineID(rawValue: 2), to: .hours(open: 1_439, close: 1_442))
        try batched.setStationDemand(a, to: StationDemand(kind: .residential, dailyTrips: 100_000))
        try batched.setStationDemand(c, to: StationDemand(kind: .office, dailyTrips: 100_000))
        var stepped = batched
        try batched.advance(ticks: 8)
        for _ in 0..<8 { try stepped.advance(ticks: 1) }
        XCTAssertEqual(batched, stepped)
        XCTAssertGreaterThan(batched.passengerLedger(of: a).released, 0)
        try assertConservedAndSaveable(batched)
    }

    func testAWindowThatNeverRunsItsPlannedLevelAbandonsTheQueue() throws {
        var world = try world()
        let journey = try XCTUnwrap(PassengerJourney(origin: a, route: XCTUnwrap(world.passengerRoutes(from: a, to: c).first)))
        world.passengers[0].release(5, along: journey, at: GameTime(minutes: -1))
        try world.setLineTrainsInService(LineID(rawValue: 2), to: TrainsInService(peak: 1, offPeak: 0, low: 0))
        XCTAssertEqual(world.passengerLedger(of: a).waiting, 5, "the next peak still runs")
        try world.setLineServiceWindow(LineID(rawValue: 2), to: .hours(open: 0, close: 60))
        XCTAssertEqual(world.passengerLedger(of: a).abandoned, 5)
        try assertConservedAndSaveable(world)
    }

    /// Nobody changes trains at a closed station (the reference's
    /// `metroStationAllowsTransfer`): B is where the lines meet.
    func testNoOneChangesTrainsAtAClosedStation() throws {
        var world = try world()
        let journey = try XCTUnwrap(PassengerJourney(origin: a, route: XCTUnwrap(world.passengerRoutes(from: a, to: c).first)))
        world.passengers[0].release(5, along: journey, at: GameTime(minutes: -1))
        try world.setStationOperationMode(b, to: .closed)
        XCTAssertEqual(world.passengerRoutes(from: a, to: c), [])
        XCTAssertEqual(world.passengerLedger(of: a).waiting, 0, "their change at B is gone")
        XCTAssertEqual(world.passengerLedger(of: a).abandoned, 5)
        try world.setStationOperationMode(b, to: .flowControl)
        XCTAssertFalse(world.passengerRoutes(from: a, to: c).isEmpty, "flow control still lets them change")
    }

    /// Riders bound for a station that closes on the way cannot get off
    /// there and cannot ride on past it: they leave the train there,
    /// counted as abandoned at their origin, and every step stays saveable.
    func testRidersBoundForAClosedStationOnTheWayLeaveThere() throws {
        var world = try world()
        world.setPassengerRoutingMode(.direct)
        let through = try world.createLine(named: "Through", stops: [a, b, c]).id
        try world.setLineServiceWindow(through, to: .allDay)
        try world.setLineTrainsInService(through, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        let one = TrainID(rawValue: 1)
        try world.unassignTrain(one)
        try world.assignTrain(one, to: through)
        let origin = try XCTUnwrap(world.passengers.firstIndex { $0.station == a })
        world.passengers[origin].release(5, to: b, along: PassengerTrip(line: through, direction: .outbound),
                                         at: world.clock.now)
        try world.advance(ticks: 1)
        XCTAssertEqual(world.riderCount(of: one), 5)
        try world.setStationOperationMode(b, to: .closed)
        for _ in 0..<6 {
            try world.advance(ticks: 1)
            try assertConservedAndSaveable(world)
        }
        XCTAssertEqual(world.riderCount(of: one), 0)
        XCTAssertEqual(world.passengerLedger(of: a).abandoned, 5)
        XCTAssertEqual(world.passengerLedger(of: a).arrived, 0)
    }

    func testInvalidRouteCreditStateIsRejected() throws {
        var world = try world()
        try world.setStationDemand(a, to: StationDemand(kind: .residential, dailyTrips: 100_000))
        try world.setStationDemand(c, to: StationDemand(kind: .office, dailyTrips: 100_000))
        try world.advance(ticks: 1)
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(world)) as? [String: Any])
        let balances = try XCTUnwrap(saved["passengerRouteBalances"] as? [[String: Any]])
        XCTAssertFalse(balances.isEmpty)
        func rejects(_ edit: (inout [String: Any]) throws -> Void) throws {
            var object = saved
            var entries = balances
            try edit(&entries[0])
            object["passengerRouteBalances"] = entries
            XCTAssertThrowsError(try JSONDecoder().decode(GameWorld.self, from: JSONSerialization.data(withJSONObject: object)))
        }
        try rejects { $0["weights"] = [Int64.max] }
        try rejects { $0["origin"] = 99 }
        try rejects { entry in
            var journeys = try XCTUnwrap(entry["journeys"] as? [[String: Any]])
            journeys[0]["current"] = 1
            entry["journeys"] = journeys
        }
        try rejects { entry in
            let journeys = try XCTUnwrap(entry["journeys"] as? [[String: Any]])
            entry["journeys"] = [journeys[0], journeys[0]]
            entry["weights"] = [1, 1]
            entry["balances"] = [0, 0]
        }
        // A next ride that starts out of walking reach of the last.
        try rejects { entry in
            var journeys = try XCTUnwrap(entry["journeys"] as? [[String: Any]])
            var legs = try XCTUnwrap(journeys[0]["legs"] as? [[String: Any]])
            guard legs.count == 2 else { return XCTFail("A to C changes at B") }
            legs[1]["from"] = 99
            journeys[0]["legs"] = legs
            entry["journeys"] = journeys
        }
    }
}

/// Changing trains between two stations a short walk apart (Phase 5F): the
/// `Railway/` site's under-450 m transfer rule.
final class WalkingTransferTests: XCTestCase {
    private let a = StationID(rawValue: 1)
    private let b = StationID(rawValue: 2)
    private let near = StationID(rawValue: 3)
    private let c = StationID(rawValue: 4)

    /// A at column 1 and B at 3 on the first line; the second line runs from
    /// B's neighbour 32 m east of it to C, 496 m further on.
    private func world() throws -> GameWorld {
        var world = try makeWorld(width: 65_536, height: 4_096, balance: 1_000_000)
        let track = TestLine(tiles: 38)
        try track.build(in: &world)
        for (name, x) in [("A", 1), ("B", 3), ("Near", 5), ("C", 36)] {
            try track.buildStation(named: name, beside: x, at: 1, in: &world)
        }
        let first = try world.createLine(named: "First", stops: [a, b]).id
        let second = try world.createLine(named: "Second", stops: [near, c]).id
        for line in [first, second] {
            try world.setLineServiceWindow(line, to: .allDay)
            try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        }
        let one = try world.purchaseTrain(named: "One").id
        let two = try world.purchaseTrain(named: "Two").id
        try world.placeTrain(one, at: track.at(1, facingEast: true))
        try world.placeTrain(two, at: track.at(5, facingEast: true))
        try world.setTrainMovementRate(one, to: 1024)
        try world.setTrainMovementRate(two, to: 1024)
        try world.assignTrain(one, to: first)
        try world.assignTrain(two, to: second)
        try world.setStationDemand(a, to: StationDemand(kind: .residential, dailyTrips: 0))
        world.setPassengerRoutingMode(.network)
        world.setSpeed(.normal)
        return world
    }

    func testWalksFollowTheDistanceAtTheReferenceSpeedAndTiers() throws {
        let world = try world()
        // 32 m: a same-platform change (over 20 m, up to 50 m), 23.04 s at
        // 5 km/h, rounded up.
        XCTAssertEqual(world.walkingTransfer(from: b, to: near)?.seconds, 24)
        XCTAssertEqual(world.walkingTransfer(from: b, to: near)?.tier, .samePlatform)
        XCTAssertEqual(world.walkingTransfer(from: near, to: b)?.seconds, 24)
        // 64 m: a passage, 46.08 s.
        XCTAssertEqual(world.walkingTransfer(from: a, to: near)?.seconds, 47)
        XCTAssertEqual(world.walkingTransfer(from: a, to: near)?.tier, .passage)
        XCTAssertNil(world.walkingTransfer(from: b, to: b))
        // 496 m is past the 450 m limit.
        XCTAssertNil(world.walkingTransfer(from: near, to: c))
        XCTAssertNil(world.walkingTransfer(from: b, to: StationID(rawValue: 99)))
        // Exactly on the limit is too far; just inside it walks.
        let limit = GameWorld.walkingTransferMetres * WorldCoordinate.unitsPerMetre
        let origin = PlanPoint(x: 0, y: 0)
        XCTAssertNil(PassengerWalk(from: origin, to: PlanPoint(x: limit, y: 0), station: c))
        XCTAssertEqual(PassengerWalk(from: origin, to: PlanPoint(x: limit - 1, y: 0), station: c)?.seconds, 324)
        XCTAssertEqual(PassengerWalk(from: origin, to: PlanPoint(x: limit - 1, y: 0), station: c)?.tier, .virtual)
    }

    func testTiersPenaltiesAndWalkTimesFollowTheReference() {
        func tier(_ units: Int64) -> PassengerTransferTier? {
            PassengerTransferTier.of(squaredDistance: units * units)
        }
        let metre = WorldCoordinate.unitsPerMetre
        XCTAssertEqual(tier(0), .overlap)
        XCTAssertEqual(tier(20 * metre), .overlap)
        XCTAssertEqual(tier(20 * metre + 1), .samePlatform)
        XCTAssertEqual(tier(50 * metre), .samePlatform)
        XCTAssertEqual(tier(50 * metre + 1), .passage)
        XCTAssertEqual(tier(250 * metre), .passage)
        XCTAssertEqual(tier(250 * metre + 1), .virtual)
        XCTAssertEqual(tier(450 * metre - 1), .virtual)
        XCTAssertNil(tier(450 * metre), "strictly less than 450 m")
        XCTAssertEqual(PassengerTransferTier.allCases.map(\.penaltySeconds), [720, 720, 1_080, 1_530])
        XCTAssertEqual(PassengerTransferRules.minimumChangeSeconds, 120)
        // 5 km/h: 100 m in 72 s, 1 m in 0.72 s (rounded up to 1 s).
        XCTAssertEqual(PassengerTransferTier.walkSeconds(squaredDistance: (100 * metre) * (100 * metre)), 72)
        XCTAssertEqual(PassengerTransferTier.walkSeconds(squaredDistance: metre * metre), 1)
        XCTAssertEqual(PassengerTransferTier.walkSeconds(squaredDistance: 0), 0)
    }

    func testRouteWalksBetweenNearbyStations() throws {
        let world = try world()
        let route = try XCTUnwrap(world.passengerRoutes(from: a, to: c).first)
        XCTAssertEqual(route.legs.map(\.from), [a, near])
        XCTAssertEqual(route.legs.map(\.to), [b, c])
        XCTAssertEqual(route.transfers, 1)
        // 32 m: a same-platform change, 15 min × 0.8, and a 24 s walk.
        XCTAssertEqual(route.transferMinutes, 12)
        XCTAssertEqual(route.walkMinutes, 1)
        // A walk never ends a journey: every route to Near rides into it.
        let toNear = world.passengerRoutes(from: a, to: near)
        XCTAssertFalse(toNear.isEmpty)
        XCTAssertTrue(toNear.allSatisfy { $0.legs.last?.to == near })
        XCTAssertNotNil(PassengerJourney(origin: a, route: route))
    }

    func testPassengersWalkToTheNextTrainAndStayConserved() throws {
        var world = try world()
        let journey = try XCTUnwrap(PassengerJourney(origin: a, route: XCTUnwrap(world.passengerRoutes(from: a, to: c).first)))
        world.passengers[0].release(5, along: journey, at: world.clock.now)

        try world.advance(ticks: 1)
        XCTAssertEqual(world.riders(of: TrainID(rawValue: 1)).map(\.count), [5])
        try world.advance(ticks: 1)
        XCTAssertEqual(world.riders(of: TrainID(rawValue: 1)), [])
        XCTAssertEqual(world.waitingPassengers(at: b), [])
        let walking = try XCTUnwrap(world.waitingPassengers(at: near).first)
        XCTAssertEqual(walking.journey?.origin, a)
        XCTAssertEqual(walking.journey?.current, 1)
        XCTAssertEqual(walking.count, 5)
        // The reference's least change time, longer than the 24 s walk.
        XCTAssertEqual(walking.readyAt, GameTime(seconds: walking.since.seconds + 120))
        XCTAssertEqual(world.passengerLedger(of: a).waiting, 5)
        XCTAssertEqual(world.passengerLedger(of: near).released, 0)
        XCTAssertEqual(world.passengerLedger(of: near).waiting, 0)

        var loaded = try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world))
        XCTAssertEqual(loaded, world)
        var batched = world
        try batched.advance(ticks: 60)
        for _ in 0..<60 { try loaded.advance(ticks: 1) }
        XCTAssertEqual(batched, loaded)
        let ledger = batched.passengerLedger(of: a)
        XCTAssertEqual(ledger.released, 5)
        XCTAssertEqual(ledger.arrived, 5)
        XCTAssertEqual(ledger.waiting + ledger.riding + ledger.overflowed + ledger.abandoned, 0)
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(batched)), batched)
    }

    func testRemovingTheWalkedToLineAbandonsAtTheOrigin() throws {
        var world = try world()
        let journey = try XCTUnwrap(PassengerJourney(origin: a, route: XCTUnwrap(world.passengerRoutes(from: a, to: c).first)))
        world.passengers[0].release(5, along: journey, at: GameTime(minutes: -1))
        try world.removeLine(LineID(rawValue: 2))
        let ledger = world.passengerLedger(of: a)
        XCTAssertEqual(ledger.abandoned, 5)
        XCTAssertEqual(ledger.waiting, 0)
    }

    func testNetworkDemandWalksAndBatchMatchesMinuteSteps() throws {
        var batched = try world()
        try batched.setStationDemand(a, to: StationDemand(kind: .residential, dailyTrips: 2_000))
        try batched.setStationDemand(c, to: StationDemand(kind: .office, dailyTrips: 2_000))
        var stepped = batched
        try batched.advance(ticks: 90)
        for _ in 0..<90 { try stepped.advance(ticks: 1) }
        XCTAssertEqual(batched, stepped)
        let ledger = batched.passengerLedger(of: a)
        XCTAssertGreaterThan(ledger.released, 0)
        XCTAssertGreaterThan(ledger.arrived, 0)
        XCTAssertEqual(ledger.released,
            ledger.waiting + ledger.riding + ledger.arrived + ledger.overflowed + ledger.abandoned)
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(batched)), batched)
    }

    func testASaveWithAJourneyOutOfWalkingReachIsRefused() throws {
        var world = try world()
        let route = try XCTUnwrap(world.passengerRoutes(from: a, to: c).first)
        world.passengers[0].release(5, along: try XCTUnwrap(PassengerJourney(origin: a, route: route)), at: GameTime(minutes: -1))
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(world)
        XCTAssertNoThrow(try JSONDecoder().decode(GameWorld.self, from: data))
        // Move the walked-to station 500 m away in the save's text.
        var json = try XCTUnwrap(String(data: data, encoding: .utf8))
        let point = TestLine.centre(5, 1)
        let moved = #"{"x":\#(point.x + 500 * 64),"y":\#(point.y)}"#
        let original = #"{"x":\#(point.x),"y":\#(point.y)}"#
        XCTAssertEqual(json.components(separatedBy: original).count, 2, "The station's point appears once")
        json = json.replacingOccurrences(of: original, with: moved)
        XCTAssertThrowsError(try JSONDecoder().decode(GameWorld.self, from: Data(json.utf8)))
    }
}
