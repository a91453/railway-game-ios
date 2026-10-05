import Foundation
@testable import GameCore
import XCTest

final class ScheduledOvertakeTrackTests: XCTestCase {
    static func threeTrains(departure: Int64 = 350) throws -> GameWorld {
        var world = try ScheduledTrafficTests.overtake()
        let peer = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.forward(5), offset: 5_120, cars: 1)
        try world.setTrainTimetable(peer, to: [
            .init(station: SingleTrackMeet.middle, arrival: .init(seconds: 0), departure: .init(seconds: departure)),
            .init(station: SingleTrackMeet.east, arrival: .init(seconds: 900), departure: .init(seconds: 960)),
        ])
        try world.startTrainService(peer)
        return world
    }

    func testThirdTrainOnTheLoopPreventsTheV3Overtake() throws {
        let two = try ScheduledTrafficTests.overtake(), three = try Self.threeTrains()
        XCTAssertTrue(two.scheduledTrafficWaits().contains { $0.kind == .overtake })
        XCTAssertFalse(three.scheduledTrafficWaits().contains { $0.kind == .overtake && $0.train.rawValue == 1 })
        XCTAssertEqual(three.scheduledTrafficWaits(), ScheduledTrafficTests.model(for: three).scheduledPlan().waits)
    }

    /// Slow arrives at 180, waits until 360: padded interval [150,390].
    /// A peer departing at exactly 150 still blocks; 149 no longer does.
    func testPaddedWindowIncludesBothEndpoints() throws {
        let world = try Self.threeTrains()
        var plan = world.trafficPlan()
        var oracle = ScheduledTrafficTests.model(for: world).scheduledPlan()
        let model = ScheduledTrafficTests.model(for: world)
        plan.waits = []; oracle.waits = []
        plan.services[2].points[0].departure = 150
        oracle.services[2].visits[0].dep = 150
        XCTAssertFalse(world.overtakeTrackFree(&plan, service: 0, at: 1, departure: 360))
        XCTAssertFalse(model.freeOvertakeTrack(&oracle, 0, 1, 360))
        plan.services[2].points[0].departure = 149
        oracle.services[2].visits[0].dep = 149
        XCTAssertTrue(world.overtakeTrackFree(&plan, service: 0, at: 1, departure: 360))
        XCTAssertTrue(model.freeOvertakeTrack(&oracle, 0, 1, 360))
        plan.services[2].points[0].arrival = 390
        plan.services[2].points[0].departure = 400
        oracle.services[2].visits[0].arr = 390; oracle.services[2].visits[0].dep = 400
        XCTAssertFalse(world.overtakeTrackFree(&plan, service: 0, at: 1, departure: 360))
        XCTAssertFalse(model.freeOvertakeTrack(&oracle, 0, 1, 360))
        plan.services[2].points[0].arrival = 391
        oracle.services[2].visits[0].arr = 391
        XCTAssertTrue(model.freeOvertakeTrack(&oracle, 0, 1, 360))
        XCTAssertTrue(world.overtakeTrackFree(&plan, service: 0, at: 1, departure: 360))
    }

    func testEarlierPlannedDwellWinsAndArrivalTiesUseID() throws {
        let world = try Self.threeTrains()
        var plan = world.trafficPlan()
        let model = ScheduledTrafficTests.model(for: world)
        var oracle = model.scheduledPlan()
        plan.waits = [.init(train: .init(rawValue: 3), station: SingleTrackMeet.middle, stop: 0, cycle: 0,
                            other: .init(rawValue: 2), otherStop: 1, otherCycle: 0, kind: .overtake,
                            departure: .init(seconds: 350), clearance: 30)]
        oracle.waits = plan.waits
        plan.services[2].points[0].arrival = 179
        oracle.services[2].visits[0].arr = 179
        XCTAssertFalse(model.freeOvertakeTrack(&oracle, 0, 1, 360))
        XCTAssertFalse(world.overtakeTrackFree(&plan, service: 0, at: 1, departure: 360))
        plan.services[2].points[0].arrival = 180
        oracle.services[2].visits[0].arr = 180
        XCTAssertTrue(model.freeOvertakeTrack(&oracle, 0, 1, 360))
        XCTAssertTrue(world.overtakeTrackFree(&plan, service: 0, at: 1, departure: 360), "ID 1 wins over ID 3 at equal arrival")
        plan.services[2].points[0].arrival = 181
        oracle.services[2].visits[0].arr = 181
        XCTAssertTrue(model.freeOvertakeTrack(&oracle, 0, 1, 360))
        XCTAssertTrue(world.overtakeTrackFree(&plan, service: 0, at: 1, departure: 360))
    }

    /// With two candidates a peer can block A OR B, so one remains.
    /// A second peer blocking A makes a combination covering both possible.
    func testEveryCombinationOfKnownPeerRoutesMustLeaveATrack() throws {
        let world = try Self.threeTrains()
        var plan = world.trafficPlan(); plan.waits = []
        let model = ScheduledTrafficTests.model(for: world)
        var oracle = model.scheduledPlan(); oracle.waits = []
        let a = Set<TrackResource>([.span(.init(edge: .edge(5), start: 3_072, end: 5_120))])
        let b = Set<TrackResource>([.span(.init(edge: .edge(2), start: 7_168, end: 9_216))])
        let berth = GameWorld.Berth(traversal: SingleTrackMeet.forward(5), offset: 5_120)
        let key = GameWorld.TrafficMoveKey(service: 0, point: 1)
        plan.sidings[key] = [.init(berth: berth, body: a, route: a), .init(berth: berth, body: b, route: b)]
        plan.moves[.init(service: 1, point: 1)] = [.init(berth: berth, body: [], route: a), .init(berth: berth, body: [], route: b)]
        let run = ReferenceWorld.Run(SingleTrackMeet.forward(5))!
        func move(_ body: Set<TrackResource>, _ route: Set<TrackResource>) -> ReferenceWorld.StationMove {
            .init(run: run, offset: 5_120, body: body, route: route, directions: [])
        }
        let oracleKey = ReferenceWorld.StationMoveKey(service: 0, visit: 1)
        oracle.places[oracleKey] = [move(a, a), move(b, b)]
        oracle.movements[.init(service: 1, visit: 1)] = [move([], a), move([], b)]
        plan.services[2].points[0].arrival = 391
        oracle.services[2].visits[0].arr = 391
        XCTAssertTrue(model.freeOvertakeTrack(&oracle, 0, 1, 360))
        XCTAssertTrue(world.overtakeTrackFree(&plan, service: 0, at: 1, departure: 360))
        plan.services[2].points[0].arrival = 390
        plan.moves[.init(service: 2, point: 0)] = [.init(berth: berth, body: [], route: a)]
        oracle.services[2].visits[0].arr = 390
        oracle.movements[.init(service: 2, visit: 0)] = [move([], a)]
        XCTAssertFalse(model.freeOvertakeTrack(&oracle, 0, 1, 360))
        XCTAssertFalse(world.overtakeTrackFree(&plan, service: 0, at: 1, departure: 360))
        plan.moves[.init(service: 2, point: 0)] = []
        oracle.movements[.init(service: 2, visit: 0)] = []
        XCTAssertFalse(model.freeOvertakeTrack(&oracle, 0, 1, 360))
        XCTAssertFalse(world.overtakeTrackFree(&plan, service: 0, at: 1, departure: 360), "unknown movement is conservative")
        plan.sidings[key] = Array(repeating: .init(berth: berth, body: a, route: a), count: 31)
        oracle.places[oracleKey] = Array(repeating: move(a, a), count: 31)
        XCTAssertFalse(model.freeOvertakeTrack(&oracle, 0, 1, 360))
        XCTAssertFalse(world.overtakeTrackFree(&plan, service: 0, at: 1, departure: 360), "source's 30-track guard")
    }

    /// The earlier dwell chooses its berth before a later dwell. Including
    /// the latter's original route would incorrectly eliminate that berth.
    func testLaterPlannedDwellDoesNotBlockEarlierBerthPreference() throws {
        let world = try Self.threeTrains(), model = ScheduledTrafficTests.model(for: world)
        var plan = world.trafficPlan(), oracle = model.scheduledPlan()
        let slow = try XCTUnwrap(world.train(id: .init(rawValue: 1)))
        let start = try XCTUnwrap(slow.position)
        let normal = try XCTUnwrap(world.path(from: start, toStation: SingleTrackMeet.middle, length: slow.length))
        plan.waits = [
            .init(train: slow.id, station: SingleTrackMeet.middle, stop: 1, cycle: 0,
                  other: .init(rawValue: 2), otherStop: 1, otherCycle: 0, kind: .overtake,
                  departure: .init(seconds: 360), clearance: 30),
            .init(train: .init(rawValue: 3), station: SingleTrackMeet.middle, stop: 0, cycle: 0,
                  other: .init(rawValue: 2), otherStop: 1, otherCycle: 0, kind: .overtake,
                  departure: .init(seconds: 350), clearance: 30),
        ]
        oracle.waits = plan.waits
        plan.services[2].points[0].arrival = 181; oracle.services[2].visits[0].arr = 181
        let chosen = world.scheduledBerthPath(slow, from: start, target: SingleTrackMeet.middle, stop: 1,
                                              normal: normal, plan: plan, berthPenalty: [:], edgePenalty: [:])
        let expected = model.scheduledBerthRoute(model.trains[0], SingleTrackMeet.middle, 1, normal, oracle, [:], [:])
        XCTAssertNotNil(chosen)
        XCTAssertEqual(chosen, expected)
        XCTAssertEqual(chosen?.traversals.last?.edge, .edge(5))
    }

    /// Hand-built safe candidates isolate selection from the window oracle.
    /// The main berth is nearer, but its 800 m cost makes the loop win.
    /// An empty eligible set must not silently admit any station berth.
    func testSafeBerthsKeepGeneralizedCostsAndEmptySelection() throws {
        let world = try ScheduledTrafficTests.overtake(), model = ScheduledTrafficTests.model(for: world)
        var plan = world.trafficPlan(), oracle = model.scheduledPlan()
        let slow = try XCTUnwrap(world.train(id: .init(rawValue: 1))), start = try XCTUnwrap(slow.position)
        let normal = try XCTUnwrap(world.path(from: start, toStation: SingleTrackMeet.middle, length: slow.length))
        let main = plan.services[0].points[1].berth
        let loop = try XCTUnwrap(world.trafficOvertakeTracks(&plan, service: 0, at: 1).first)
        XCTAssertLessThan(normal.distance, try XCTUnwrap(world.trafficPath(from: start, toStation: SingleTrackMeet.middle, length: slow.length,
                                                                         berthPenalty: [:], edgePenalty: [:], only: loop.berth)).distance)
        plan.sidings[.init(service: 0, point: 1)] = [.init(berth: main, body: [], route: []), .init(berth: loop.berth, body: [], route: [])]
        let mainRun = ReferenceWorld.Run(main.traversal)!, loopRun = ReferenceWorld.Run(loop.berth.traversal)!
        oracle.places[.init(service: 0, visit: 1)] = [
            .init(run: mainRun, offset: main.offset, body: [], route: [], directions: []),
            .init(run: loopRun, offset: loop.berth.offset, body: [], route: [], directions: []),
        ]
        let chosen = world.scheduledBerthPath(slow, from: start, target: SingleTrackMeet.middle, stop: 1,
                                              normal: normal, plan: plan, berthPenalty: [main: 51_200], edgePenalty: [:])
        XCTAssertEqual(chosen, model.scheduledBerthRoute(model.trains[0], SingleTrackMeet.middle, 1, normal, oracle, [mainRun: 51_200], [:]))
        XCTAssertEqual(chosen?.traversals.last?.edge, loop.berth.traversal.edge)
        XCTAssertNil(world.trafficPath(from: start, toStation: SingleTrackMeet.middle, length: slow.length,
                                      berthPenalty: [:], edgePenalty: [:], eligible: []))
        XCTAssertNil(model.networkPathToStation(from: start, station: SingleTrackMeet.middle, length: slow.length, eligible: [:]))
    }

    func testTrafficOffAndSaveRoundTripKeepTheThreeTrainState() throws {
        var world = try Self.threeTrains()
        try world.setTrafficControl(false)
        var model = ScheduledTrafficTests.model(for: world)
        XCTAssertEqual(world.scheduledTrafficWaits(), [])
        try world.advance(ticks: 20)
        XCTAssertNil(model.advance(ticks: 20))
        XCTAssertEqual(KernelDifferentialTests.differences(world, model), [])
        XCTAssertTrue(world.trains.allSatisfy { $0.trafficVisits.isEmpty })
        let loaded = try JSONDecoder().decode(SavedGame.self, from: JSONEncoder().encode(SavedGame(world: world)))
        XCTAssertEqual(loaded.world, world)
    }
}
