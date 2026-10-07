import Foundation
@testable import GameCore
import XCTest

final class TurnbackTests: XCTestCase {
    /// A--C--B on one physical track; the service calls A, B, C. It must
    /// reverse at the intermediate B in both halves of its round trip.
    static func switchback(control: Bool = true, cars: Int = 3) throws -> (GameWorld, ReferenceWorld, LineID, TrainID) {
        let costs = ConstructionCosts(track: 0, station: 0, train: 0, car: 0)
        var world = try GameWorld(bounds: .init(width: 40_960, height: 12_288), economy: .init(balance: 1_000_000, costs: costs), clock: .init(speed: .x1))
        var model = ReferenceWorld(width: 40_960, height: 12_288, balance: 1_000_000, costs: costs, seconds: 0, speed: .x1)
        for x: Int64 in [1_024, 33_792] {
            let point = WorldCoordinate(x: x, y: 4_096)
            try world.buildTrackNode(at: point); XCTAssertNil(model.buildNetworkNode(at: point))
        }
        try world.buildTrackEdge(from: .node(1), to: .node(2))
        XCTAssertNil(model.buildNetworkEdge(from: .node(1), to: .node(2), curve: .straight))
        var stops: [StationID] = []
        for (name, low, high): (String, Int64, Int64) in [("A", 2_048, 4_096), ("B", 24_576, 26_624), ("C", 12_288, 14_336)] {
            let point = PlanPoint(x: high, y: 8_192)
            let station = try world.buildStation(named: name, at: point).id
            XCTAssertNil(model.buildStation(named: name, at: point))
            try world.addTrackPlatform(station, on: .edge(1), from: low, to: high)
            XCTAssertNil(model.addTrackPlatform(station, on: .edge(1), from: low, to: high))
            stops.append(station)
        }
        let line = try world.createLine(named: "Switchback", stops: stops).id
        XCTAssertNil(model.createLine(named: "Switchback", stops: stops))
        try world.setLineServiceWindow(line, to: .allDay); XCTAssertNil(model.setLineWindow(line, .allDay))
        let counts = TrainsInService(peak: 1, offPeak: 1, low: 1)
        try world.setLineTrainsInService(line, to: counts); XCTAssertNil(model.setLineTrains(line, counts))
        let train = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.forward(1), offset: 4_096, cars: cars)
        XCTAssertNil(model.purchaseTrain(named: "T")); XCTAssertNil(model.setCars(train, cars))
        XCTAssertNil(model.placeTrain(train, at: .onEdge(SingleTrackMeet.forward(1), offset: 4_096)))
        XCTAssertNil(model.setContinuation(train, along: [], stoppingAt: 4_096)); XCTAssertNil(model.setRate(train, 1_024))
        try world.assignTrain(train, to: line); XCTAssertNil(model.assign(train, to: line))
        try world.setTrafficControl(control); XCTAssertNil(model.setTrafficControl(control))
        return (world, model, line, train)
    }

    static func reverseSiding(shortSiding: Bool = false, shortStart: Bool = false) throws -> (GameWorld, ReferenceWorld, TrainID, TrainID) {
        var world = try SingleTrackMeet.world()
        var model = SingleTrackMeet.model()
        try world.removeTrackEdge(.edge(4)); XCTAssertNil(model.removeNetworkEdge(.edge(4)))
        if shortSiding {
            try world.removeTrackPlatform(SingleTrackMeet.middle, on: .edge(5), from: 3_072)
            XCTAssertNil(model.removeTrackPlatform(SingleTrackMeet.middle, on: .edge(5), from: 3_072))
            try world.addTrackPlatform(SingleTrackMeet.middle, on: .edge(5), from: 3_072, to: 3_584)
            XCTAssertNil(model.addTrackPlatform(SingleTrackMeet.middle, on: .edge(5), from: 3_072, to: 3_584))
        }
        let point = PlanPoint(x: 28_672, y: 8_192)
        let a = try world.buildStation(named: "A", at: point).id
        XCTAssertNil(model.buildStation(named: "A", at: point))
        try world.addTrackPlatform(a, on: .edge(3), from: shortStart ? 2_560 : 2_048, to: 4_096)
        XCTAssertNil(model.addTrackPlatform(a, on: .edge(3), from: shortStart ? 2_560 : 2_048, to: 4_096))
        var ids: [TrainID] = []
        for (track, calls) in [(SingleTrackMeet.forward(3), [a, SingleTrackMeet.east]),
                               (SingleTrackMeet.backward(3), [SingleTrackMeet.east, SingleTrackMeet.west])] {
            let id = try SingleTrackMeet.stand(&world, edge: track, offset: 3_072)
            XCTAssertNil(model.purchaseTrain(named: "T")); XCTAssertNil(model.setCars(id, 2))
            XCTAssertNil(model.placeTrain(id, at: .onEdge(track, offset: 3_072)))
            XCTAssertNil(model.setContinuation(id, along: [], stoppingAt: 3_072)); XCTAssertNil(model.setRate(id, 1_024))
            let table = calls.enumerated().map {
                ScheduledStop(station: $0.element, arrival: .init(seconds: Int64($0.offset) * 240), departure: .init(seconds: Int64($0.offset) * 240))
            }
            try world.setTrainTimetable(id, to: table); XCTAssertNil(model.setTimetable(id, table))
            try world.startTrainService(id); XCTAssertNil(model.startService(id))
            ids.append(id)
        }
        try world.setTrafficControl(true); XCTAssertNil(model.setTrafficControl(true))
        world.setSpeed(.x1); model.setSpeed(.x1)
        return (world, model, ids[0], ids[1])
    }

    /// Taking a train off a line with a mid-route turnback while it carries
    /// passengers beyond the turnback: off the line the turnback ends its
    /// direction (``GameWorld/directionEnd(of:from:)``), so those riders
    /// leave at once, counted as abandoned, and the world still loads.
    func testUnassigningASwitchbackTrainWithRidersStillLoads() throws {
        var (world, _, line, train) = try Self.switchback()
        let a = StationID(rawValue: 1), c = StationID(rawValue: 3)
        for station in [a, StationID(rawValue: 2), c] {
            try world.setStationDemand(station, to: StationDemand(kind: .office, dailyTrips: 0))
        }
        let record = try XCTUnwrap(world.passengers.firstIndex { $0.station == a })
        world.passengers[record].release(5, to: c, along: PassengerTrip(line: line, direction: .outbound), at: .zero)
        var boarded = false
        for _ in 0..<1_200 {
            try world.advance(ticks: 1)
            if world.riderCount(of: train) > 0, case .travellingToStop(1, _)? = world.train(id: train)?.execution {
                boarded = true
                break
            }
        }
        XCTAssertTrue(boarded)
        XCTAssertNil(world.riderProblem())
        try world.unassignTrain(train)
        XCTAssertNil(world.riderProblem())
        XCTAssertNil(world.passengerProblem())
        XCTAssertEqual(world.riderCount(of: train), 0)
        XCTAssertEqual(world.passengerLedger(of: a).abandoned, 5)
        XCTAssertNoThrow(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world)))
    }

    func testReverseSidingSkipsNearMainBerthAndBothTrainsFinish() throws {
        var (world, model, east, west) = try Self.reverseSiding()
        try world.advance(ticks: 590); XCTAssertNil(model.advance(ticks: 590))
        XCTAssertEqual(world.deadlockedTrains(), [east, west])
        var memo = GameWorld.DirectionMemo()
        let stuck = world.deadlock(memo: &memo)
        let way = try XCTUnwrap(world.passingPlace(for: try XCTUnwrap(stuck[east]).candidate, in: stuck, memo: &memo))
        XCTAssertTrue(way.reverses)
        XCTAssertEqual(way.path.distance, 11_900)
        XCTAssertEqual(way.path.traversals, [SingleTrackMeet.backward(6), SingleTrackMeet.backward(5)])
        XCTAssertEqual(way.path.end, 5_120)
        XCTAssertEqual(way.distance, 27_896)
        var batched = world
        var sawSiding = false
        for second in 60...600 {
            try world.advance(ticks: 10); XCTAssertNil(model.advance(ticks: 10))
            XCTAssertEqual(KernelDifferentialTests.differences(world, model), [], "second \(second)")
            XCTAssertEqual(world.deadlockedTrains(), model.deadlockedTrains())
            XCTAssertEqual(WorldInvariants.violations(in: world), [])
            if world.passingPlace(of: east) == SingleTrackMeet.middle { sawSiding = true }
            if [60, 100, 120, 180, 300].contains(second) { XCTAssertNil(WorldInvariants.roundTripProblem(of: world)) }
        }
        try batched.advance(ticks: 5_410)
        XCTAssertEqual(world, batched)
        XCTAssertTrue(sawSiding)
        XCTAssertNil(world.train(id: east)?.execution)
        XCTAssertNil(world.train(id: west)?.execution)
        XCTAssertEqual(world.stationsStoppedAt(by: east), [SingleTrackMeet.east])
        XCTAssertEqual(world.stationsStoppedAt(by: west), [SingleTrackMeet.west])
    }

    func testBlockedOrShortSidingAndShortDeparturePlatformDoNotTurnTheTrain() throws {
        for kind in 0..<4 {
            var (world, model, east, west) = try Self.reverseSiding(shortSiding: kind == 1, shortStart: kind == 2)
            if kind == 0 || kind == 3 {
                // The fourth case holds the junction from the main track:
                // the siding edge itself is empty, but its entrance fouls.
                let track = SingleTrackMeet.forward(kind == 3 ? 2 : 5)
                let offset: Int64 = kind == 3 ? 16_384 : 4_096
                let parked = try world.purchaseTrain(named: "T").id
                try world.setTrainCars(parked, to: 2)
                try world.placeTrain(parked, at: .onEdge(track, offset: offset))
                let end: Int64? = kind == 3 ? nil : offset
                try world.setTrainContinuation(parked, along: [], stoppingAt: end)
                try world.setTrainMovementRate(parked, to: 1_024)
                XCTAssertNil(model.purchaseTrain(named: "T")); XCTAssertNil(model.setCars(parked, 2))
                XCTAssertNil(model.placeTrain(parked, at: .onEdge(track, offset: offset)))
                XCTAssertNil(model.setContinuation(parked, along: [], stoppingAt: end)); XCTAssertNil(model.setRate(parked, 1_024))
            }
            let position = world.train(id: east)?.position
            let trail = world.train(id: east)?.trailEdges
            for _ in 0..<180 {
                try world.advance(ticks: 10); XCTAssertNil(model.advance(ticks: 10))
                XCTAssertEqual(KernelDifferentialTests.differences(world, model), [])
                XCTAssertEqual(world.train(id: east)?.position, position)
                XCTAssertEqual(world.train(id: east)?.trailEdges, trail)
                XCTAssertEqual(world.reservedResources(of: east), [])
                XCTAssertEqual(WorldInvariants.violations(in: world), [])
            }
            XCTAssertEqual(world.deadlockedTrains(), [east, west])
        }
    }

    func testSidingWaitKeepsItsFacingUntilAnAtomicDepartureAndSurvivesControlToggle() throws {
        var (world, model, east, west) = try Self.reverseSiding()
        var arrived = false
        for _ in 0..<180 {
            try world.advance(ticks: 10); XCTAssertNil(model.advance(ticks: 10))
            if world.passingPlace(of: east) == SingleTrackMeet.middle { arrived = true; break }
        }
        XCTAssertTrue(arrived)
        let facing = world.train(id: east)?.position
        XCTAssertEqual(facing, .onEdge(SingleTrackMeet.backward(5), offset: 5_120))
        XCTAssertEqual(world.trainHoldingRoute(of: east), west)
        let before = world
        // Read-only planning can propose the reversed candidate; it cannot
        // commit its orientation or a partial reservation while held.
        _ = world.goingOn(try XCTUnwrap(world.train(id: east)))
        XCTAssertEqual(world, before)
        try world.advance(ticks: 10); XCTAssertNil(model.advance(ticks: 10))
        XCTAssertEqual(world.train(id: east)?.position, facing)
        XCTAssertEqual(world.reservedResources(of: east), [])
        XCTAssertEqual(KernelDifferentialTests.differences(world, model), [])
        let data = try JSONEncoder().encode(SavedGame(world: world))
        var restored = try JSONDecoder().decode(SavedGame.self, from: data).world
        try world.setTrafficControl(false); XCTAssertNil(model.setTrafficControl(false))
        try restored.setTrafficControl(false)
        try world.advance(ticks: 10); XCTAssertNil(model.advance(ticks: 10)); try restored.advance(ticks: 10)
        XCTAssertEqual(world, restored)
        XCTAssertEqual(KernelDifferentialTests.differences(world, model), [])
        guard case .onEdge(let track, _)? = world.train(id: east)?.position else { return XCTFail("missing train") }
        XCTAssertEqual(track.direction, .forward)
        XCTAssertEqual(world.reservedResources(of: east), [])
    }

    func testRateZeroFreezesABackingRunAndResumesWithoutLosingItsReservation() throws {
        var (world, model, east, _) = try Self.reverseSiding()
        try world.advance(ticks: 700); XCTAssertNil(model.advance(ticks: 700))
        try world.setTrainMovementRate(east, to: 0); XCTAssertNil(model.setRate(east, 0))
        let position = world.train(id: east)?.position
        let reserved = world.reservedResources(of: east)
        XCTAssertFalse(reserved.isEmpty)
        try world.advance(ticks: 500); XCTAssertNil(model.advance(ticks: 500))
        XCTAssertEqual(world.train(id: east)?.position, position)
        XCTAssertEqual(world.reservedResources(of: east), reserved)
        XCTAssertEqual(KernelDifferentialTests.differences(world, model), [])
        XCTAssertNil(WorldInvariants.roundTripProblem(of: world))
        try world.setTrainMovementRate(east, to: 1_024); XCTAssertNil(model.setRate(east, 1_024))
        try world.advance(ticks: 6_000); XCTAssertNil(model.advance(ticks: 6_000))
        XCTAssertEqual(KernelDifferentialTests.differences(world, model), [])
        XCTAssertNil(world.train(id: east)?.execution)
        XCTAssertEqual(world.stationsStoppedAt(by: east), [SingleTrackMeet.east])
    }

    func testUndispatchedSwitchbackProtectsBothDirectionsOfItsFullPlan() throws {
        var (world, model, _, _) = try Self.switchback()
        let id = try world.purchaseTrain(named: "Probe").id
        XCTAssertNil(model.purchaseTrain(named: "Probe"))
        var memo = GameWorld.DirectionMemo()
        let protected = world.opposingServiceTraversals(for: try XCTUnwrap(world.train(id: id)), memo: &memo)
        XCTAssertEqual(protected, [SingleTrackMeet.forward(1), SingleTrackMeet.backward(1)])
        let reference = model.contraryRuns(for: try XCTUnwrap(model.trains.first { $0.id == id.rawValue }))
        XCTAssertEqual(Set(reference.map(\.traversal)), protected)
    }

    /// Platform preferences on the two turnback legs (B to C, B to A) are
    /// matched from the turned placement, chosen whole at departure, and
    /// protected in both directions before the line sends a train out.
    func testPreferencesOnTurnbackLegsAreMatchedFromTheTurnedPlacement() throws {
        var (world, model, id, train) = try Self.switchback()
        let stops = try XCTUnwrap(world.line(id: id)).stops
        let routes = [LineRoutePreference(from: 1, to: 2, platform: world.trackPlatforms(of: stops[2])[0]),
                      LineRoutePreference(from: 1, to: 0, platform: world.trackPlatforms(of: stops[0])[0])]
        try world.setLineRoutePreferences(id, to: routes); XCTAssertNil(model.setLineRoutes(id, routes))
        let line = try XCTUnwrap(world.line(id: id)), placed = try XCTUnwrap(world.train(id: train))
        let trip = try XCTUnwrap(world.trip(of: line, service: 0, for: placed))
        XCTAssertFalse(trip.turnsFirst)
        XCTAssertEqual(trip.journey.intermediateTurnbacks, [1, 3])
        XCTAssertEqual(trip.journey.legs.map(\.path.distance), [22_528, 12_288, 12_288, 22_528])
        XCTAssertEqual(world.matchedRoutes(trip.journey, routes: routes, start: try XCTUnwrap(placed.placement)), 2)
        let driver = try XCTUnwrap(model.trains.first { $0.id == train.rawValue })
        XCTAssertEqual(model.matchedRoutes(trip.journey, routes: routes, start: driver), 2)
        let probe = try world.purchaseTrain(named: "Probe").id
        XCTAssertNil(model.purchaseTrain(named: "Probe"))
        var memo = GameWorld.DirectionMemo()
        let protected = world.opposingServiceTraversals(for: try XCTUnwrap(world.train(id: probe)), memo: &memo)
        XCTAssertEqual(protected, [SingleTrackMeet.forward(1), SingleTrackMeet.backward(1)])
        XCTAssertEqual(Set(model.contraryRuns(for: try XCTUnwrap(model.trains.first { $0.id == probe.rawValue })).map(\.traversal)), protected)
        var batched = world
        for second in 1...510 {
            try world.advance(ticks: 10); XCTAssertNil(model.advance(ticks: 10))
            XCTAssertEqual(KernelDifferentialTests.differences(world, model), [], "second \(second)")
            XCTAssertEqual(WorldInvariants.violations(in: world), [])
        }
        try batched.advance(ticks: 5_100)
        XCTAssertEqual(world, batched)
        XCTAssertNil(world.train(id: train)?.execution)
        XCTAssertEqual(world.stationsStoppedAt(by: train), [stops[0]])
    }

    func testWholeTrainSwitchbackHasHandTimedLegsAndTurnsOnlyAtDeparture() throws {
        var (world, model, id, train) = try Self.switchback()
        let line = try XCTUnwrap(world.line(id: id)), placed = try XCTUnwrap(world.train(id: train))
        let trip = try XCTUnwrap(world.trip(of: line, service: 0, for: placed))
        XCTAssertFalse(trip.turnsFirst)
        XCTAssertEqual(trip.journey.intermediateTurnbacks, [1, 3])
        XCTAssertEqual(trip.journey.legs.map(\.path.distance), [22_528, 12_288, 12_288, 22_528])
        // Standard triangular runs: ceil(sqrt(distance * 0.12)), giving
        // ceil(51.994...) and ceil(38.4), below the 110 km/h speed cap.
        XCTAssertEqual(trip.journey.legs.map(\.seconds), [52, 39, 39, 52])
        XCTAssertEqual(trip.journey.roundTripSeconds, 542)
        let timetable = try XCTUnwrap(trip.timetable(calling: line.stops, sentOutAt: .init(seconds: 0)))
        XCTAssertEqual(timetable.map(\.arrival.seconds), [0, 94, 193, 352, 464])
        XCTAssertEqual(timetable.map(\.departure.seconds), [42, 154, 313, 412, 464])
        XCTAssertEqual(timetable.map(\.reverses), [false, true, true, true, true])
        for second in 1...510 {
            try world.advance(ticks: 10); XCTAssertNil(model.advance(ticks: 10))
            XCTAssertEqual(KernelDifferentialTests.differences(world, model), [], "second \(second)")
            XCTAssertEqual(world.scheduledTrafficWaits(), model.scheduledPlan().waits)
            XCTAssertEqual(world.deadlockedTrains(), model.deadlockedTrains())
            XCTAssertEqual(WorldInvariants.violations(in: world), [])
            if second == 94 || second == 154 {
                XCTAssertEqual(world.train(id: train)?.position, .onEdge(SingleTrackMeet.forward(1), offset: 26_624))
                XCTAssertEqual(world.stationsBesideWholeTrain(train), [line.stops[1]])
            }
            if second == 155 {
                guard case .onEdge(let track, _)? = world.train(id: train)?.position else { return XCTFail("missing train") }
                XCTAssertEqual(track.direction, .backward)
                XCTAssertFalse(world.reservedResources(of: train).isEmpty)
            }
            if [94, 154, 155, 194, 413].contains(second) { XCTAssertNil(WorldInvariants.roundTripProblem(of: world)) }
        }
        XCTAssertNil(world.train(id: train)?.execution)
        XCTAssertEqual(world.stationsStoppedAt(by: train), [line.stops[0]])
    }

    func testControlOffKeepsTheForwardOnlyJourneyAndAnOverlongTrainIsNotDispatched() throws {
        var (world, model, line, train) = try Self.switchback(control: false)
        XCTAssertNil(world.lineJourney(line))
        try world.advance(ticks: 600); XCTAssertNil(model.advance(ticks: 600))
        XCTAssertNil(world.train(id: train)?.execution)
        XCTAssertEqual(KernelDifferentialTests.differences(world, model), [])
        let (long, _, id, unit) = try Self.switchback(cars: 4)
        XCTAssertNil(long.trip(of: try XCTUnwrap(long.line(id: id)), service: 0, for: try XCTUnwrap(long.train(id: unit))))
    }
}
