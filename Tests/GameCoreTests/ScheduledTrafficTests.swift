import Foundation
@testable import GameCore
import XCTest

final class ScheduledTrafficTests: XCTestCase {
    static func meet() throws -> GameWorld {
        var world = try SingleTrackMeet.world()
        let east = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.forward(1), offset: 3_072)
        let west = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.backward(3), offset: 3_072)
        try world.setTrainTimetable(east, to: [
            .init(station: SingleTrackMeet.west, arrival: .init(seconds: 0), departure: .init(seconds: 60)),
            .init(station: SingleTrackMeet.east, arrival: .init(seconds: 660), departure: .init(seconds: 720)),
        ])
        try world.setTrainTimetable(west, to: [
            .init(station: SingleTrackMeet.east, arrival: .init(seconds: 0), departure: .init(seconds: 120)),
            .init(station: SingleTrackMeet.middle, arrival: .init(seconds: 400), departure: .init(seconds: 460)),
            .init(station: SingleTrackMeet.west, arrival: .init(seconds: 760), departure: .init(seconds: 820)),
        ])
        try world.startTrainService(east)
        try world.startTrainService(west)
        try world.setTrafficControl(true)
        return world
    }

    static func overtake(fastDeparture: Int64 = 180, fastArrival: Int64 = 600, scale: Int64 = 1) throws -> GameWorld {
        var world = try SingleTrackMeet.world(scale: scale)
        let beyond = try world.buildTrackNode(at: WorldCoordinate(x: 35_840 * scale, y: 4_096 * scale))
        let edge = try world.buildTrackEdge(from: .node(4), to: beyond)
        let terminus = try world.buildStation(named: "F", at: PlanPoint(x: 35_840 * scale, y: 8_192 * scale)).id
        try world.addTrackPlatform(terminus, on: edge, from: 512 * scale, to: 1_536 * scale)
        let slow = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.forward(1), offset: 3_072 * scale, cars: 1)
        let fast = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.forward(1), offset: 1_024 * scale, cars: 1)
        try world.setTrainTimetable(slow, to: [
            .init(station: SingleTrackMeet.west, arrival: .init(seconds: 0), departure: .init(seconds: 60)),
            .init(station: SingleTrackMeet.middle, arrival: .init(seconds: 180), departure: .init(seconds: 180)),
            .init(station: SingleTrackMeet.east, arrival: .init(seconds: 900), departure: .init(seconds: 960)),
        ])
        try world.setTrainTimetable(fast, to: [
            .init(station: SingleTrackMeet.west, arrival: .init(seconds: 0), departure: .init(seconds: fastDeparture)),
            .init(station: terminus, arrival: .init(seconds: fastArrival), departure: .init(seconds: fastArrival + 60)),
        ])
        try world.startTrainService(slow)
        try world.startTrainService(fast)
        try world.setTrafficControl(true)
        return world
    }

    func testMeetUsesTheStationAtTheEndOfTheSingleTrack() throws {
        var world = try Self.meet()
        let plan = world.scheduledTrafficWaits()
        XCTAssertEqual(plan.count, 1)
        let wait = try XCTUnwrap(plan.first)
        XCTAssertEqual(wait.train.rawValue, 1)
        XCTAssertEqual(wait.other.rawValue, 2)
        XCTAssertEqual(wait.station, SingleTrackMeet.middle)
        XCTAssertEqual(wait.kind, .meet)
        XCTAssertEqual(wait.clearance, 20) // floor((460 − 400) / 3)
        XCTAssertEqual(wait.departure.seconds, 420)
        try world.advance(ticks: 6)
        world.setSpeed(.x1)
        try world.advance(ticks: 20)
        world.setSpeed(.normal)
        XCTAssertEqual(world.scheduledTrafficWait(of: .init(rawValue: 1))?.station, SingleTrackMeet.middle)
        try world.advance(ticks: 12)
        XCTAssertTrue(world.trains.allSatisfy { $0.execution == nil })
        XCTAssertEqual(WorldInvariants.violations(in: world), [])
    }

    func testRouteHolderQueryKeepsTheScheduledWaypoint() throws {
        var world = try Self.meet()
        var model = Self.model(for: world)
        try world.advance(ticks: 1)
        XCTAssertNil(model.advance(ticks: 1))
        // The route only goes to M's loop, so the peer standing at E does
        // not block this departure. Queries must use that same waypoint.
        let own = TrainID(rawValue: 1)
        XCTAssertNil(world.trainHoldingRoute(of: own))
        XCTAssertNil(model.trainHoldingRoute(of: own))
        XCTAssertEqual(KernelDifferentialTests.differences(world, model, lineAnswers: false), [])
    }

    func testSlowTrainWaitsOnTheLoopAndFastTrainUsesTheMain() throws {
        var world = try Self.overtake()
        let wait = try XCTUnwrap(world.scheduledTrafficWaits().first { $0.kind == .overtake })
        XCTAssertEqual(wait.train.rawValue, 1)
        XCTAssertEqual(wait.other.rawValue, 2)
        XCTAssertEqual(wait.station, SingleTrackMeet.middle)
        try world.advance(ticks: 5)
        guard case .onEdge(let loop, _)? = world.train(id: .init(rawValue: 1))?.position else { return XCTFail("slow unplaced") }
        XCTAssertEqual(loop.edge, .edge(5))
        XCTAssertNotNil(world.scheduledTrafficWait(of: .init(rawValue: 1)))
        try world.advance(ticks: 15)
        XCTAssertTrue(world.trains.allSatisfy { $0.execution == nil })
    }

    static func model(for world: GameWorld) -> ReferenceWorld {
        var model = SingleTrackMeet.model()
        if world.stations.count == 4 {
            precondition(model.buildNetworkNode(at: WorldCoordinate(x: 35_840, y: 4_096)) == nil)
            precondition(model.buildNetworkEdge(from: .node(4), to: .node(7), curve: .straight) == nil)
            precondition(model.buildStation(named: "F", at: PlanPoint(x: 35_840, y: 8_192)) == nil)
            precondition(model.addTrackPlatform(StationID(rawValue: 4), on: .edge(7), from: 512, to: 1_536) == nil)
        }
        for train in world.trains {
            precondition(model.purchaseTrain(named: train.name) == nil)
            precondition(model.setCars(train.id, train.cars) == nil)
            precondition(model.placeTrain(train.id, at: train.position!) == nil)
            precondition(model.setContinuation(train.id, along: [], stoppingAt: train.movement.end) == nil)
            precondition(model.setRate(train.id, train.movement.rate) == nil)
            precondition(model.setTimetable(train.id, train.timetable) == nil)
            if train.execution != nil { precondition(model.startService(train.id) == nil) }
        }
        for line in world.lines {
            precondition(model.createLine(named: line.name, stops: line.stops) == nil)
            precondition(model.setLinePerformance(line.id, line.performance) == nil)
            precondition(model.setLineWindow(line.id, line.window) == nil)
            precondition(model.setLineTrains(line.id, line.trainsInService) == nil)
            for train in line.trains { precondition(model.assign(train, to: line.id) == nil) }
        }
        precondition(model.setTrafficControl(true) == nil)
        return model
    }

    func testIndependentModelAgreesAtEverySecond() throws {
        for initial in [try Self.meet(), try Self.overtake()] {
            var world = initial
            var model = Self.model(for: initial)
            world.setSpeed(.x1); model.setSpeed(.x1)
            XCTAssertEqual(world.scheduledTrafficWaits(), model.scheduledPlan().waits)
            for second in 0..<1_400 {
                try world.advance(ticks: 10)
                XCTAssertNil(model.advance(ticks: 10))
                let differences = KernelDifferentialTests.differences(world, model)
                guard differences.isEmpty else { return XCTFail("second \(second + 1): \(differences.joined(separator: "\n"))") }
                XCTAssertEqual(world.scheduledTrafficWaits(), model.scheduledPlan().waits, "second \(second + 1)")
            }
        }
    }

    func testDelayedOpponentMustReallyArrive() throws {
        var world = try Self.meet()
        try world.setTrainMovementRate(TrainID(rawValue: 2), to: 0)
        try world.advance(ticks: 10)
        XCTAssertEqual(world.scheduledTrafficWait(of: TrainID(rawValue: 1))?.other.rawValue, 2)
        XCTAssertTrue(world.train(id: TrainID(rawValue: 2))!.trafficVisits.isEmpty)
        let data = try JSONEncoder().encode(SavedGame(world: world))
        let loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(loaded, world)
        var resumed = loaded
        try resumed.setTrainMovementRate(TrainID(rawValue: 2), to: 1_024)
        try resumed.advance(ticks: 15)
        XCTAssertNil(resumed.scheduledTrafficWait(of: TrainID(rawValue: 1)))
        XCTAssertEqual(WorldInvariants.violations(in: resumed), [])
    }

    func testBatchesAndASaveInsideActualClearanceAreExact() throws {
        var batch = try Self.overtake()
        var singles = batch
        singles.setSpeed(.x1)
        try batch.advance(ticks: 20)
        for _ in 0..<1_200 { try singles.advance(ticks: 10) }
        batch.setSpeed(.x1)
        XCTAssertEqual(batch, singles)
        var atClearance = try Self.overtake()
        atClearance.setSpeed(.x1)
        try atClearance.advance(ticks: 3_900)
        let peer = try XCTUnwrap(atClearance.train(id: TrainID(rawValue: 2))?.trafficVisits.first)
        XCTAssertEqual(peer.departure, GameTime(seconds: 388))
        XCTAssertNotNil(atClearance.scheduledTrafficWait(of: TrainID(rawValue: 1)))
        var loaded = try JSONDecoder().decode(SavedGame.self, from: JSONEncoder().encode(SavedGame(world: atClearance))).world
        try loaded.advance(ticks: 270)
        XCTAssertNotNil(loaded.scheduledTrafficWait(of: TrainID(rawValue: 1))) // 417, before 388 + 30
        try loaded.advance(ticks: 10)
        XCTAssertNil(loaded.scheduledTrafficWait(of: TrainID(rawValue: 1))) // exactly 418
    }

    func testDepartureMeetWaitsForTheActualPassingTrain() throws {
        var world = try Self.meet()
        let peer = TrainID(rawValue: 2)
        try world.stopTrainService(peer)
        try world.setTrainTimetable(peer, to: [
            .init(station: SingleTrackMeet.east, arrival: .init(seconds: 0), departure: .init(seconds: 120)),
            .init(station: SingleTrackMeet.middle, arrival: .init(seconds: 250), departure: .init(seconds: 310)),
            .init(station: SingleTrackMeet.west, arrival: .init(seconds: 760), departure: .init(seconds: 820)),
        ])
        try world.startTrainService(peer)
        let wait = try XCTUnwrap(world.scheduledTrafficWaits().first)
        XCTAssertEqual(wait.train, peer)
        XCTAssertEqual(wait.other.rawValue, 1)
        XCTAssertEqual(wait.departure.seconds, 381) // passing time 361 + dwell / 3
        try world.setTrainMovementRate(wait.other, to: 0)
        try world.advance(ticks: 10)
        XCTAssertEqual(world.scheduledTrafficWait(of: peer), wait)
    }

    func testOvertakeLimitsAndTooCloseAreNotScheduled() throws {
        var world = try Self.overtake(fastDeparture: 180, fastArrival: 1_600)
        let slow = TrainID(rawValue: 1)
        try world.stopTrainService(slow)
        try world.setTrainTimetable(slow, to: [
            .init(station: SingleTrackMeet.west, arrival: .init(seconds: 0), departure: .init(seconds: 60)),
            .init(station: SingleTrackMeet.middle, arrival: .init(seconds: 180), departure: .init(seconds: 180)),
            .init(station: SingleTrackMeet.east, arrival: .init(seconds: 1_800), departure: .init(seconds: 1_860)),
        ])
        try world.startTrainService(slow)
        XCTAssertFalse(world.scheduledTrafficWaits().contains { $0.kind == .overtake }, "over 600 s")
        let close = try Self.overtake(fastDeparture: 60, fastArrival: 240)
        XCTAssertFalse(close.scheduledTrafficWaits().contains { $0.kind == .overtake }, "insufficient braking lead")

        // Hold the times/physical network fixed, vary only the common
        // interval's distance: isolate the source's 25 km eligibility gate.
        let eligible = try Self.overtake()
        var plan = eligible.trafficPlan()
        plan.waits = []
        plan.services[0].points[1].departure = 180
        plan.services[0].points[2].arrival = 3_000 // long enough to build a 25 km stopping run
        plan.services[0].points[2].departure = 3_060
        for i in plan.services.indices { plan.services[i].points[2].distance = 1_600_000 }
        var beyond = plan
        for i in beyond.services.indices { beyond.services[i].points[2].distance += 1 }
        XCTAssertTrue(eligible.planTrafficOvertakes(&plan), "exactly 25 km")
        XCTAssertFalse(eligible.planTrafficOvertakes(&beyond), "over 25 km")
        XCTAssertTrue(beyond.waits.isEmpty)
    }

    func testTheSixHundredSecondLimitIsInclusive() throws {
        let world = try Self.overtake()
        var plan = world.trafficPlan()
        plan.waits = []
        plan.services[0].points[1].departure = 180
        plan.services[0].points[2].arrival = 3_000
        plan.services[0].points[2].departure = 3_060
        plan.services[1].points[1].arrival = 750
        plan.services[1].points[1].departure = 750
        plan.services[1].points[2].arrival = 1_400
        plan.services[1].points[2].departure = 1_400
        var beyond = plan
        beyond.services[1].points[1].arrival += 1
        beyond.services[1].points[1].departure += 1
        XCTAssertTrue(world.planTrafficOvertakes(&plan))
        XCTAssertEqual(plan.waits.first?.departure.seconds, 780) // 780 − 180 = 600
        XCTAssertFalse(world.planTrafficOvertakes(&beyond))
        XCTAssertTrue(beyond.waits.isEmpty)
    }

    func testTerminalMeetUsesThirtySecondsOfClearance() throws {
        var world = try Self.meet()
        let peer = TrainID(rawValue: 2)
        try world.stopTrainService(peer)
        try world.setTrainTimetable(peer, to: [
            .init(station: SingleTrackMeet.east, arrival: .init(seconds: 0), departure: .init(seconds: 120)),
            .init(station: SingleTrackMeet.middle, arrival: .init(seconds: 400), departure: .init(seconds: 400)),
        ])
        try world.startTrainService(peer)
        let wait = try XCTUnwrap(world.scheduledTrafficWaits().first)
        XCTAssertEqual(wait.clearance, 30)
        XCTAssertEqual(wait.departure.seconds, 430)
        XCTAssertEqual(wait.other, peer)
    }

    func testMeetWindowAdjustmentLimitAndIDTies() throws {
        let world = try Self.meet()
        var plan = world.trafficPlan()
        plan.waits = []
        plan.services[0].points[1].departure = 361
        plan.services[1].points[1].arrival = 800
        plan.services[1].points[1].departure = 860
        world.inferTrafficMeets(&plan)
        XCTAssertTrue(plan.waits.isEmpty, "adjustment over 300 s")
        plan.services[1].points[1].arrival = 2_400
        plan.services[1].points[1].departure = 2_460
        world.inferTrafficMeets(&plan)
        XCTAssertTrue(plan.waits.isEmpty, "outside 1800 s window")
        var tied = world.trafficPlan()
        tied.waits = []
        tied.services[0].points[1].departure = 361
        var other = tied.services[1]
        var json = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(other.train)) as? [String: Any])
        json["id"] = 3
        other.train = try JSONDecoder().decode(Train.self, from: JSONSerialization.data(withJSONObject: json))
        tied.services.append(other)
        world.inferTrafficMeets(&tied)
        XCTAssertEqual(tied.waits.first?.other.rawValue, 2)
    }

    func testAPlacedRosterContributesItsConcreteTrip() throws {
        var world = try Self.meet()
        let peer = TrainID(rawValue: 2)
        try world.stopTrainService(peer)
        try world.setTrainTimetable(peer, to: [])
        let line = try world.createLine(named: "Westbound", stops: [SingleTrackMeet.east, SingleTrackMeet.middle, SingleTrackMeet.west])
        try world.setLineServiceWindow(line.id, to: .allDay)
        try world.setLineTrainsInService(line.id, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        try world.setLinePerformance(line.id, to: TrainPerformance(acceleration: 500, braking: 500, topSpeed: 4))
        try world.assignTrain(peer, to: line.id)
        var model = Self.model(for: world)
        let waits = world.scheduledTrafficWaits()
        XCTAssertFalse(waits.isEmpty)
        XCTAssertEqual(waits, model.scheduledPlan().waits)
        world.setSpeed(.x1); model.setSpeed(.x1)
        for second in 0..<1_000 {
            try world.advance(ticks: 10)
            XCTAssertNil(model.advance(ticks: 10))
            let differences = KernelDifferentialTests.differences(world, model)
            guard differences.isEmpty else { return XCTFail("roster second \(second + 1): \(differences.joined(separator: "\n"))") }
        }
        XCTAssertNil(world.trains[0].execution)
    }

    func testAFirstCallOnTheMainIsNotAnAvailableOvertakingBerth() throws {
        for onLoop in [false, true] {
            var world = try SingleTrackMeet.world()
            let slow = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.forward(onLoop ? 5 : 2), offset: onLoop ? 5_120 : 9_216, cars: 1)
            let fast = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.forward(1), offset: 3_072, cars: 1)
            try world.setTrainTimetable(slow, to: [
                .init(station: SingleTrackMeet.middle, arrival: .init(seconds: 0), departure: .init(seconds: 30)),
                .init(station: SingleTrackMeet.east, arrival: .init(seconds: 270), departure: .init(seconds: 330)),
            ])
            try world.setTrainTimetable(fast, to: [
                .init(station: SingleTrackMeet.west, arrival: .init(seconds: 0), departure: .init(seconds: 0)),
                .init(station: SingleTrackMeet.east, arrival: .init(seconds: 240), departure: .init(seconds: 300)),
            ])
            try world.startTrainService(slow); try world.startTrainService(fast)
            try world.setTrafficControl(true)
            let waits = world.scheduledTrafficWaits()
            XCTAssertEqual(waits, Self.model(for: world).scheduledPlan().waits)
            XCTAssertEqual(waits.contains { $0.kind == .overtake && $0.train == slow }, onLoop)
        }
    }

    func testTrafficOffHasNoPlanOrTrafficEvents() throws {
        var world = try Self.overtake()
        try world.setTrafficControl(false)
        XCTAssertEqual(world.scheduledTrafficWaits(), [])
        try world.advance(ticks: 20)
        XCTAssertTrue(world.trains.allSatisfy { $0.trafficVisits.isEmpty })
    }
}
