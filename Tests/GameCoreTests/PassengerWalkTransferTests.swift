import Foundation
@testable import GameCore
import XCTest

/// Phase 5F: walking transfers with the reference's tiers and least change
/// time, and station operation modes (`StationOperationMode`), ported from
/// the `Ci/` reference's transfer types and `operationMode`.
final class PassengerWalkTransferTests: XCTestCase {
    private let a = StationID(rawValue: 1)
    private let b = StationID(rawValue: 2)
    private let nearB = StationID(rawValue: 3)
    private let c = StationID(rawValue: 4)

    /// Two tracks 100 m apart. First runs A–B on the northern track; Second
    /// runs B'–C on the southern one, B' 100 m south of B.
    private func world(apart metres: Int64 = 100) throws -> GameWorld {
        var world = try makeWorld(width: 8_192, height: 40_960, balance: 1_000_000)
        let north = TestLine(tiles: 7)
        try north.build(in: &world)
        try north.buildStation(named: "A", beside: 1, at: 1, in: &world)
        try north.buildStation(named: "B", beside: 3, at: 1, in: &world)
        let y = TestLine.centre(0, 1).y + metres * WorldCoordinate.unitsPerMetre
        var nodes: [TrackNodeID] = []
        for x in 0..<7 {
            nodes.append(try world.buildTrackNode(at: WorldCoordinate(x: TestLine.centre(x, 1).x, y: y)))
        }
        var edges: [TrackEdgeID] = []
        for x in 1..<7 {
            edges.append(try world.buildTrackEdge(from: nodes[x - 1], to: nodes[x]))
        }
        for (name, x) in [("B'", 3), ("C", 5)] {
            let id = try world.buildStation(named: name, at: PlanPoint(x: TestLine.centre(x, 1).x, y: y)).id
            try world.addTrackPlatform(id, on: edges[x - 1], from: TestLine.tile / 2, to: TestLine.tile)
            try world.addTrackPlatform(id, on: edges[x], from: 0, to: TestLine.tile / 2)
        }
        let first = try world.createLine(named: "First", stops: [a, b]).id
        let second = try world.createLine(named: "Second", stops: [nearB, c]).id
        for line in [first, second] {
            try world.setLineServiceWindow(line, to: .allDay)
            try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        }
        let one = try world.purchaseTrain(named: "One").id
        let two = try world.purchaseTrain(named: "Two").id
        try world.placeTrain(one, at: north.at(1, facingEast: true))
        try world.placeTrain(two, at: .onEdge(TrackTraversal(edge: edges[2], direction: .forward), offset: TestLine.tile))
        try world.setTrainMovementRate(one, to: 1024)
        try world.setTrainMovementRate(two, to: 1024)
        try world.assignTrain(one, to: first)
        try world.assignTrain(two, to: second)
        try world.setStationDemand(a, to: StationDemand(kind: .residential, dailyTrips: 0))
        world.setPassengerRoutingMode(.network)
        world.setSpeed(.normal)
        return world
    }

    private func assertConservedAndSaveable(_ world: GameWorld, file: StaticString = #filePath, line: UInt = #line) throws {
        for station in world.stations {
            let ledger = world.passengerLedger(of: station.id)
            XCTAssertEqual(ledger.released,
                ledger.waiting + ledger.riding + ledger.arrived + ledger.overflowed + ledger.abandoned,
                file: file, line: line)
        }
        let saved = try JSONEncoder().encode(SavedGame(world: world))
        XCTAssertEqual(try JSONDecoder().decode(SavedGame.self, from: saved).world, world, file: file, line: line)
    }

    func testARouteWalksToAStationNearbyWithItsTierPenalty() throws {
        let world = try world()
        let route = try XCTUnwrap(world.passengerRoutes(from: a, to: c).first)
        XCTAssertEqual(route.legs.map(\.from), [a, nearB])
        XCTAssertEqual(route.legs.map(\.to), [b, c])
        XCTAssertEqual(route.walkMinutes, 2, "72 s at 5 km/h, rounded up")
        XCTAssertEqual(route.transferMinutes, 18, "a passage: 15 min × 1.2")
        XCTAssertEqual(route.transfers, 1)
        XCTAssertEqual(world.passengerRoutes(from: c, to: a).first?.legs.map(\.from), [c, b])
        XCTAssertTrue(world.passengerRoutes(from: a, to: nearB).allSatisfy { $0.legs.last?.to == nearB },
                      "no route ends with a walk")
        XCTAssertTrue(try self.world(apart: 450).passengerRoutes(from: a, to: c).isEmpty, "450 m is too far")
        XCTAssertEqual(try self.world(apart: 449).passengerRoutes(from: a, to: c).first?.transferMinutes, 26,
                       "virtual: 15 min × 1.7 = 25.5 min, rounded up")
    }

    func testPassengersWalkChangeAndArriveWithTheOriginLedger() throws {
        var world = try world()
        let route = try XCTUnwrap(world.passengerRoutes(from: a, to: c).first)
        let journey = try XCTUnwrap(PassengerJourney(origin: a, route: route))
        let origin = try XCTUnwrap(world.passengers.firstIndex { $0.station == a })
        world.passengers[origin].release(5, along: journey, at: world.clock.now)

        var walked: WaitingGroup?
        for _ in 0..<10 where walked == nil {
            try world.advance(ticks: 1)
            walked = world.waitingPassengers(at: nearB).first
        }
        let group = try XCTUnwrap(walked)
        XCTAssertEqual(group.journey?.origin, a)
        XCTAssertEqual(group.journey?.current, 1)
        XCTAssertEqual(group.count, 5)
        XCTAssertEqual(group.readyAt.map { $0.seconds - group.since.seconds }, 120,
                       "the reference's least change time, longer than the 72 s walk")
        XCTAssertEqual(world.waitingPassengers(at: b), [])
        XCTAssertEqual(world.passengerLedger(of: a).waiting, 5)
        try assertConservedAndSaveable(world)

        var loaded = try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world))
        try world.advance(ticks: 30)
        for _ in 0..<30 { try loaded.advance(ticks: 1) }
        XCTAssertEqual(world, loaded)
        XCTAssertEqual(world.passengerLedger(of: a).arrived, 5)
        try assertConservedAndSaveable(world)
    }

    func testNetworkDemandWalksAndBatchesMatchMinuteSteps() throws {
        var batched = try world()
        try batched.setStationDemand(a, to: StationDemand(kind: .residential, dailyTrips: 50_000))
        try batched.setStationDemand(c, to: StationDemand(kind: .office, dailyTrips: 50_000))
        var stepped = batched
        try batched.advance(ticks: 45)
        for _ in 0..<45 { try stepped.advance(ticks: 1) }
        XCTAssertEqual(batched, stepped)
        XCTAssertGreaterThan(batched.passengerLedger(of: a).released, 0)
        XCTAssertTrue(batched.passengers.flatMap(\.waiting).contains { $0.journey != nil && $0.journey!.current == 1 }
            || batched.passengerLedger(of: a).arrived > 0)
        try assertConservedAndSaveable(batched)
    }

    func testClosingAStationSendsItsWaitingAwayAndStopsService() throws {
        var world = try world()
        let journey = try XCTUnwrap(PassengerJourney(origin: a, route: XCTUnwrap(world.passengerRoutes(from: a, to: c).first)))
        world.passengers[0].release(5, along: journey, at: GameTime(minutes: -1))
        XCTAssertThrowsGameError(try world.setStationOperationMode(StationID(rawValue: 9), to: .closed),
                                 .unknownStation(StationID(rawValue: 9)))

        // The walk's far end closes: the journey can no longer be made.
        try world.setStationOperationMode(nearB, to: .closed)
        XCTAssertEqual(world.station(id: nearB)?.operationMode, .closed)
        XCTAssertEqual(world.passengerLedger(of: a).abandoned, 5)
        XCTAssertTrue(world.passengerRoutes(from: a, to: c).isEmpty)
        XCTAssertTrue(world.passengerRoutes(from: c, to: a).isEmpty)
        try assertConservedAndSaveable(world)

        // Open again: the route returns.
        try world.setStationOperationMode(nearB, to: .normalFlow)
        XCTAssertFalse(world.passengerRoutes(from: a, to: c).isEmpty)
    }

    func testClosingAStationClearsItsQueueToTheOriginalStation() throws {
        var world = try world()
        try world.setStationDemand(b, to: StationDemand(kind: .office, dailyTrips: 0))
        let index = try XCTUnwrap(world.passengers.firstIndex { $0.station == b })
        world.passengers[index].release(4, to: a, along: PassengerTrip(line: LineID(rawValue: 1), direction: .inbound),
                                        at: GameTime(minutes: -1))
        try world.setStationOperationMode(b, to: .closed)
        XCTAssertEqual(world.waitingPassengers(at: b), [])
        XCTAssertEqual(world.passengerLedger(of: b).abandoned, 4)
        try assertConservedAndSaveable(world)
    }

    func testNobodyBoardsOrAlightsAtAClosedStationAndRidersStayAboard() throws {
        var world = try world()
        let journey = try XCTUnwrap(PassengerJourney(origin: a, route: XCTUnwrap(world.passengerRoutes(from: a, to: c).first)))
        world.passengers[0].release(5, along: journey, at: world.clock.now)
        try world.advance(ticks: 1)
        XCTAssertEqual(world.riderCount(of: TrainID(rawValue: 1)), 5)
        try world.setStationOperationMode(b, to: .closed)
        try world.advance(ticks: 20)
        // B is where the train turns round: they could not get off there.
        XCTAssertEqual(world.passengerLedger(of: a).abandoned, 5)
        XCTAssertEqual(world.passengerLedger(of: a).arrived, 0)
        XCTAssertEqual(world.waitingPassengers(at: nearB), [])
        try assertConservedAndSaveable(world)
    }

    func testRidersBoundForAStationThatClosedStaySaveable() throws {
        var world = try world()
        let journey = try XCTUnwrap(PassengerJourney(origin: a, route: XCTUnwrap(world.passengerRoutes(from: a, to: c).first)))
        world.passengers[0].release(5, along: journey, at: world.clock.now)
        try world.advance(ticks: 1)
        XCTAssertEqual(world.riderCount(of: TrainID(rawValue: 1)), 5)
        // Their ride ends at B, now closed, and their walk starts there:
        // the save still holds them, and they leave where the train turns.
        try world.setStationOperationMode(b, to: .closed)
        try assertConservedAndSaveable(world)
        try world.setStationOperationMode(nearB, to: .closed)
        try assertConservedAndSaveable(world)
    }

    func testFlowControlStopsNewPassengersButNotArrivals() throws {
        var world = try world()
        try world.setStationDemand(a, to: StationDemand(kind: .residential, dailyTrips: 50_000))
        try world.setStationDemand(c, to: StationDemand(kind: .office, dailyTrips: 50_000))
        try world.setStationOperationMode(a, to: .flowControl)
        XCTAssertEqual(world.dailyDemand(from: a, to: c), 0)
        XCTAssertGreaterThan(world.dailyDemand(from: c, to: a), 0)
        try world.setStationOperationMode(a, to: .closed)
        XCTAssertEqual(world.dailyDemand(from: c, to: a), 0, "a closed station is no destination")
        try world.advance(ticks: 30)
        XCTAssertEqual(world.passengerLedger(of: a).released, 0)
        try assertConservedAndSaveable(world)
    }

    func testDirectDemandHonoursOperationModes() throws {
        var world = try world()
        world.setPassengerRoutingMode(.direct)
        try world.setStationDemand(a, to: StationDemand(kind: .residential, dailyTrips: 1_000))
        try world.setStationDemand(b, to: StationDemand(kind: .office, dailyTrips: 1_000))
        XCTAssertEqual(world.dailyDemand(from: a, to: b), 1_000)
        try world.setStationOperationMode(b, to: .closed)
        XCTAssertEqual(world.dailyDemand(from: a, to: b), 0)
        try world.setStationOperationMode(b, to: .flowControl)
        XCTAssertEqual(world.dailyDemand(from: a, to: b), 1_000)
        XCTAssertEqual(world.dailyDemand(from: b, to: a), 0)
    }

    func testSavedWalksAndModesAreValidated() throws {
        var world = try world()
        try world.setStationOperationMode(c, to: .flowControl)
        let journey = try XCTUnwrap(PassengerJourney(origin: a, route: XCTUnwrap(world.passengerRoutes(from: a, to: c).first)))
        world.passengers[0].release(5, along: journey, at: GameTime(minutes: -1))
        let data = try JSONEncoder().encode(SavedGame(world: world))
        let loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(loaded, world)
        XCTAssertEqual(loaded.station(id: c)?.operationMode, .flowControl)

        // A walk to a station 450 m or more away is refused.
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var saved = try XCTUnwrap(object["world"] as? [String: Any])
        var stations = try XCTUnwrap(saved["stations"] as? [[String: Any]])
        var point = try XCTUnwrap(stations[2]["point"] as? [String: Any])
        point["y"] = (point["y"] as! Int) + 400 * 64
        stations[2]["point"] = point
        saved["stations"] = stations
        object["world"] = saved
        XCTAssertThrowsError(try JSONDecoder().decode(SavedGame.self, from: JSONSerialization.data(withJSONObject: object)))

        // An unknown mode is refused.
        var modes = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var other = try XCTUnwrap(modes["world"] as? [String: Any])
        var list = try XCTUnwrap(other["stations"] as? [[String: Any]])
        list[3]["operationMode"] = "open"
        other["stations"] = list
        modes["world"] = other
        XCTAssertThrowsError(try JSONDecoder().decode(SavedGame.self, from: JSONSerialization.data(withJSONObject: modes)))
        // So is an open station written with its mode: a save has one form.
        list[3]["operationMode"] = "normalFlow"
        other["stations"] = list
        modes["world"] = other
        XCTAssertThrowsError(try JSONDecoder().decode(SavedGame.self, from: JSONSerialization.data(withJSONObject: modes)))
        list[3]["operationMode"] = nil
        other["stations"] = list
        modes["world"] = other
        XCTAssertEqual(try JSONDecoder().decode(SavedGame.self, from: JSONSerialization.data(withJSONObject: modes)).world
            .station(id: c)?.operationMode, .normalFlow)
    }


    // MARK: - Transfer groups (decision 81)

    /// 600 m is too far to walk, unless the two stations are in one
    /// transfer group: then a virtual transfer, 432 s at 5 km/h (38,400
    /// units × 3,600 / 320,000), 8 minutes rounded up.
    func testATransferGroupWalksBeyondTheLimit() throws {
        var world = try world(apart: 600)
        XCTAssertTrue(world.passengerRoutes(from: a, to: c).isEmpty)
        XCTAssertNil(world.walkingTransfer(from: b, to: nearB))

        try world.linkTransfer(b, nearB)
        let walk = try XCTUnwrap(world.walkingTransfer(from: b, to: nearB))
        XCTAssertEqual(walk.seconds, 432)
        XCTAssertEqual(walk.tier, .virtual)
        let route = try XCTUnwrap(world.passengerRoutes(from: a, to: c).first)
        XCTAssertEqual(route.legs.map(\.from), [a, nearB])
        XCTAssertEqual(route.walkMinutes, 8)
        XCTAssertEqual(route.transferMinutes, 26, "virtual: 15 min × 1.7 = 25.5 min, rounded up")
        XCTAssertNil(world.walkingTransfer(from: a, to: c), "only the group's stations")

        try world.unlinkTransfer(nearB)
        XCTAssertTrue(world.passengerRoutes(from: a, to: c).isEmpty)
    }

    /// Passengers walk across the group, change and arrive; leaving the
    /// group sends those still needing the walk away, the ledger balanced.
    func testPassengersWalkWithinAGroupAndLeaveWhenItGoes() throws {
        var world = try world(apart: 600)
        try world.linkTransfer(b, nearB)
        let journey = try XCTUnwrap(PassengerJourney(origin: a, route: XCTUnwrap(world.passengerRoutes(from: a, to: c).first)))
        world.passengers[0].release(5, along: journey, at: world.clock.now)
        var walked: WaitingGroup?
        for _ in 0..<15 where walked == nil {
            try world.advance(ticks: 1)
            walked = world.waitingPassengers(at: nearB).first
        }
        let group = try XCTUnwrap(walked)
        XCTAssertEqual(group.readyAt.map { $0.seconds - group.since.seconds }, 432, "the walk, longer than 120 s")
        try assertConservedAndSaveable(world)
        var arrived = world
        try arrived.advance(ticks: 40)
        XCTAssertEqual(arrived.passengerLedger(of: a).arrived, 5)
        try assertConservedAndSaveable(arrived)

        var left = try self.world(apart: 600)
        try left.linkTransfer(b, nearB)
        left.passengers[0].release(5, along: journey, at: left.clock.now)
        try left.unlinkTransfer(b)
        XCTAssertEqual(left.passengerLedger(of: a).abandoned, 5, "the walk is gone")
        try assertConservedAndSaveable(left)
    }
}
