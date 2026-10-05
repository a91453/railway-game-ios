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
            precondition(model.setTimetable(train.id, train.timetable, period: train.timetablePeriod) == nil)
            precondition(model.startService(train.id) == nil)
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
        for i in plan.services.indices { plan.services[i].points[2].distance = 1_600_001 }
        XCTAssertFalse(eligible.planTrafficOvertakes(&plan), "over 25 km")
        XCTAssertTrue(plan.waits.isEmpty)
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

    /// Both trains run out and back on repeating timetables. The plan has
    /// the eastbound train wait on M's loop for the westbound one, which
    /// calls at M: its scheduled berth is that loop, and the main line is
    /// a direction the eastbound train's next cycle takes (decision 57),
    /// so before decision 59's fallback it could go nowhere, and both
    /// stood for ever with no deadlock reported.
    static func repeatingMeet() throws -> GameWorld {
        var world = try SingleTrackMeet.world()
        let east = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.forward(1), offset: 3_072)
        let west = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.backward(3), offset: 3_072)
        try world.setTrainTimetable(east, to: [
            .init(station: SingleTrackMeet.west, arrival: .init(seconds: 0), departure: .init(seconds: 60)),
            .init(station: SingleTrackMeet.east, arrival: .init(seconds: 660), departure: .init(seconds: 720), reverses: true),
            .init(station: SingleTrackMeet.west, arrival: .init(seconds: 1_300), departure: .init(seconds: 1_360), reverses: true),
        ], repeatingEvery: 1_500)
        try world.setTrainTimetable(west, to: [
            .init(station: SingleTrackMeet.east, arrival: .init(seconds: 0), departure: .init(seconds: 120)),
            .init(station: SingleTrackMeet.middle, arrival: .init(seconds: 400), departure: .init(seconds: 460)),
            .init(station: SingleTrackMeet.west, arrival: .init(seconds: 760), departure: .init(seconds: 820), reverses: true),
            .init(station: SingleTrackMeet.east, arrival: .init(seconds: 1_400), departure: .init(seconds: 1_460), reverses: true),
        ], repeatingEvery: 1_500)
        try world.startTrainService(east)
        try world.startTrainService(west)
        try world.setTrafficControl(true)
        return world
    }

    func testRepeatingOutAndBackServicesKeepRunning() throws {
        var world = try Self.repeatingMeet()
        let wait = try XCTUnwrap(world.scheduledTrafficWaits().first)
        XCTAssertEqual(wait.train.rawValue, 1)
        XCTAssertEqual(wait.station, SingleTrackMeet.middle)
        try world.advance(ticks: 75) // 4500 s, three cycles
        for train in world.trains {
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(train.execution).cycle, 2, "train \(train.id.rawValue)")
        }
        XCTAssertEqual(world.deadlockedTrains(), [])
        XCTAssertEqual(WorldInvariants.violations(in: world), [])
    }

    func testRepeatingOutAndBackAgreesWithTheModelAtEverySecond() throws {
        var world = try Self.repeatingMeet()
        var model = Self.model(for: world)
        world.setSpeed(.x1); model.setSpeed(.x1)
        for second in 0..<3_100 {
            try world.advance(ticks: 10)
            XCTAssertNil(model.advance(ticks: 10))
            let differences = KernelDifferentialTests.differences(world, model)
            guard differences.isEmpty else { return XCTFail("second \(second + 1): \(differences.joined(separator: "\n"))") }
            if second % 50 == 0 {
                XCTAssertEqual(world.scheduledTrafficWaits(), model.scheduledPlan().waits, "second \(second + 1)")
                for train in world.trains {
                    let expected = model.waitingScheduled(model.trains.first { $0.id == train.id.rawValue }!, plan: model.scheduledPlan())
                    XCTAssertEqual(world.scheduledTrafficWait(of: train.id), expected, "second \(second + 1), train \(train.id.rawValue)")
                }
            }
        }
    }

    /// The westbound service repeats; a third train joins at 1200 s and
    /// meets its second cycle. The plan follows the trains' state, not
    /// the advance it was worked out in: one call of 3300 s ends exactly
    /// where 3300 calls of a second do (decision 59, point 9).
    func secondCycleMeet(advancingBy chunk: Int64) throws -> GameWorld {
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
            .init(station: SingleTrackMeet.west, arrival: .init(seconds: 760), departure: .init(seconds: 820), reverses: true),
            .init(station: SingleTrackMeet.east, arrival: .init(seconds: 1_400), departure: .init(seconds: 1_460), reverses: true),
        ], repeatingEvery: 1_500)
        try world.startTrainService(east)
        try world.startTrainService(west)
        try world.setTrafficControl(true)
        world.setSpeed(.x1)
        for _ in 0..<900 { try world.advance(ticks: 10) }
        try world.unplaceTrain(east)
        for _ in 0..<300 { try world.advance(ticks: 10) }
        let late = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.forward(1), offset: 3_072)
        try world.setTrainTimetable(late, to: [
            .init(station: SingleTrackMeet.west, arrival: .init(seconds: 1_200), departure: .init(seconds: 1_560)),
            .init(station: SingleTrackMeet.east, arrival: .init(seconds: 2_160), departure: .init(seconds: 2_220)),
        ])
        try world.startTrainService(late)
        for _ in 0..<(3_300 / chunk) { try world.advance(ticks: Int(chunk * 10)) }
        return world
    }

    func testOneLongAdvanceEndsWhereSecondsDo() throws {
        let seconds = try secondCycleMeet(advancingBy: 1)
        XCTAssertEqual(try secondCycleMeet(advancingBy: 60), seconds)
        XCTAssertEqual(try secondCycleMeet(advancingBy: 3_300), seconds)
        XCTAssertTrue(seconds.trains.contains { $0.trafficVisits.contains { $0.cycle == 1 } }, "the second cycle's meet is planned and seen")
    }

    /// The westbound train cannot come: M's main platform is taken by a
    /// parked train and its loop by the eastbound train waiting there. A
    /// wait for a train that itself waits for a route is dropped, so the
    /// eastbound train asks for its route like any other (and V2 can see
    /// it) instead of waiting to meet a train that never arrives.
    func testAWaitForATrainThatCannotComeIsDropped() throws {
        var world = try Self.meet()
        let parked = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.forward(2), offset: 9_216)
        let east = TrainID(rawValue: 1), west = TrainID(rawValue: 2)
        XCTAssertEqual(world.scheduledTrafficWaits().first?.train, east)
        try world.advance(ticks: 10)
        XCTAssertNotNil(world.trainHoldingRoute(of: west), "the westbound train waits for its route")
        XCTAssertNil(world.scheduledTrafficWait(of: east))
        XCTAssertEqual(world.stationsStoppedAt(by: east), [SingleTrackMeet.middle])
        XCTAssertEqual(world.trainHoldingRoute(of: east), west)
        XCTAssertNil(world.train(id: parked)?.execution)
        XCTAssertEqual(WorldInvariants.violations(in: world), [])
    }

    /// A service that has ended without visiting the station waited at
    /// (here it saw only its first stop) will not come: the wait ends.
    func testAWaitForAServiceThatHasEndedEnds() throws {
        let world = try Self.meet()
        let wait = try XCTUnwrap(world.trafficPlan().waits.first)
        XCTAssertNil(world.trafficReleased(wait))
        var stopped = world
        try stopped.stopTrainService(wait.other)
        var save = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(SavedGame(world: stopped))) as? [String: Any])
        var json = try XCTUnwrap(save["world"] as? [String: Any])
        var trains = try XCTUnwrap(json["trains"] as? [[String: Any]])
        let index = try XCTUnwrap(trains.firstIndex { $0["id"] as? Int == Int(wait.other.rawValue) })
        trains[index]["trafficVisits"] = [["station": Int(SingleTrackMeet.east.rawValue), "stop": 0, "cycle": 0, "arrival": 0, "departure": 0]]
        json["trains"] = trains
        save["world"] = json
        let ended = try JSONDecoder().decode(SavedGame.self, from: JSONSerialization.data(withJSONObject: save)).world
        XCTAssertNil(ended.train(id: wait.other)?.execution)
        XCTAssertFalse(try XCTUnwrap(ended.train(id: wait.other)).trafficVisits.isEmpty)
        XCTAssertEqual(ended.trafficReleased(wait), ended.clock.now)
    }

    /// SingleTrackMeet with E moved east of the single track and given a
    /// loop like M's (e7 main, e9 loop); a parked train holds E's main.
    static func loopAtTheEnd() throws -> (world: GameWorld, east: TrainID, west: TrainID) {
        var world = try GameWorld(bounds: WorldBounds(width: 52_224, height: 12_288), economy: GameEconomy(balance: 1_000_000, costs: SingleTrackMeet.costs), clock: GameClock(speed: .normal))
        for point in SingleTrackMeet.points() { _ = try world.buildTrackNode(at: point) }
        for (x, y) in [(50_176, 4_096), (37_888, 6_144), (46_080, 6_144)] as [(Int64, Int64)] { _ = try world.buildTrackNode(at: WorldCoordinate(x: x, y: y)) }
        let (entrance, exit) = SingleTrackMeet.curves()
        for edge in 1...3 { _ = try world.buildTrackEdge(from: .node(edge), to: .node(edge + 1)) }
        _ = try world.buildTrackEdge(from: .node(2), to: .node(5), curve: entrance)
        _ = try world.buildTrackEdge(from: .node(5), to: .node(6))
        _ = try world.buildTrackEdge(from: .node(6), to: .node(3), curve: exit)
        _ = try world.buildTrackEdge(from: .node(4), to: .node(7))
        _ = try world.buildTrackEdge(from: .node(4), to: .node(8), curve: .cubic(.init(x: 35_840, y: 4_096), .init(x: 35_840, y: 6_144)))
        _ = try world.buildTrackEdge(from: .node(8), to: .node(9))
        _ = try world.buildTrackEdge(from: .node(9), to: .node(7), curve: .cubic(.init(x: 48_128, y: 6_144), .init(x: 48_128, y: 4_096)))
        for (name, x) in [("W", Int64(3_072)), ("M", 17_408), ("E", 41_984)] {
            _ = try world.buildStation(named: name, at: PlanPoint(x: x, y: 8_192))
        }
        for (station, edge, start, end) in [(SingleTrackMeet.west, 1, 1_024, 3_072), (SingleTrackMeet.middle, 2, 7_168, 9_216), (SingleTrackMeet.middle, 5, 3_072, 5_120),
                                            (SingleTrackMeet.east, 7, 7_168, 9_216), (SingleTrackMeet.east, 9, 3_072, 5_120)] as [(StationID, Int, Int64, Int64)] {
            try world.addTrackPlatform(station, on: .edge(edge), from: start, to: end)
        }
        let east = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.forward(1), offset: 3_072)
        let west = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.backward(9), offset: 5_120)
        _ = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.forward(7), offset: 9_216)
        try world.setTrainTimetable(east, to: [
            .init(station: SingleTrackMeet.west, arrival: .init(seconds: 0), departure: .init(seconds: 60)),
            .init(station: SingleTrackMeet.east, arrival: .init(seconds: 900), departure: .init(seconds: 960)),
        ])
        try world.setTrainTimetable(west, to: [
            .init(station: SingleTrackMeet.east, arrival: .init(seconds: 0), departure: .init(seconds: 120)),
            .init(station: SingleTrackMeet.middle, arrival: .init(seconds: 400), departure: .init(seconds: 460)),
            .init(station: SingleTrackMeet.west, arrival: .init(seconds: 760), departure: .init(seconds: 820)),
        ])
        try world.startTrainService(east)
        try world.startTrainService(west)
        try world.setTrafficControl(true)
        return (world, east, west)
    }

    /// Going on from the meet, the eastbound train cannot have its
    /// scheduled way to E's main platform (the parked train is there), so
    /// it goes on as decision 58 has it: to E's loop (decision 57), off
    /// its timetable, as fast as it can, not in the timetable's seconds.
    func testGoingOnByAnotherWayRunsAsFastAsItCan() throws {
        var (world, east, west) = try Self.loopAtTheEnd()
        let wait = try XCTUnwrap(world.scheduledTrafficWaits().first)
        XCTAssertEqual(wait.train, east)
        XCTAssertEqual(wait.other, west)
        XCTAssertEqual(wait.station, SingleTrackMeet.middle)
        world.setSpeed(.x1)
        var left: Train?
        for _ in 0..<900 {
            try world.advance(ticks: 10)
            let train = try XCTUnwrap(world.train(id: east))
            if train.execution == .travellingToStop(1), !world.stationsStoppedAt(by: east).contains(SingleTrackMeet.middle),
               train.trafficVisits.contains(where: { $0.station == SingleTrackMeet.middle && $0.departure != nil }) {
                left = train
                break
            }
        }
        let going = try XCTUnwrap(left, "the eastbound train goes on from M")
        XCTAssertTrue(going.movement.edges.contains(.edge(9)), "to E's loop: \(going.movement.edges)")
        let run = try XCTUnwrap(going.times?.run)
        XCTAssertEqual(run.seconds, RunningCurve.leastSeconds(length: run.length, performance: going.performance))
        try world.advance(ticks: 9_000)
        XCTAssertNil(world.train(id: east)?.execution)
        XCTAssertEqual(world.stationsStoppedAt(by: east), [SingleTrackMeet.east])
        XCTAssertEqual(WorldInvariants.violations(in: world), [])
    }

    func testTrafficOffHasNoPlanOrTrafficEvents() throws {
        var world = try Self.overtake()
        try world.setTrafficControl(false)
        XCTAssertEqual(world.scheduledTrafficWaits(), [])
        try world.advance(ticks: 20)
        XCTAssertTrue(world.trains.allSatisfy { $0.trafficVisits.isEmpty })
    }
}
